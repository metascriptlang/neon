#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <thread>
#include "../../src/platform/windows/image.h"
#include "../../src/platform/windows/imageDecode.h"

static HANDLE decodedWake, downloadedWake;
static std::atomic<int> decoded{0}, downloaded{0}, probes{0};
static std::atomic<bool> wrongApartment{false};
static DWORD host;

static void require(bool ok, const char *message) {
	if (!ok) {
		fprintf(stderr, "image-id assertion: %s\n", message);
		exit(1);
	}
}

extern "C" void ionWakeLoop(void) {
	downloaded.fetch_add(1);
	SetEvent(downloadedWake);
}

static void postDecoded(void) {
	decoded.fetch_add(1);
	SetEvent(decodedWake);
}

extern "C" void imageWorkerDecodeProbe(void) {
	APTTYPE type;
	APTTYPEQUALIFIER qualifier;
	if (GetCurrentThreadId() == host || FAILED(CoGetApartmentType(&type, &qualifier)) || type != APTTYPE_MTA) {
		wrongApartment.store(true);
	}
	probes.fetch_add(1);
}

extern "C" void imageDecodeJobDoneProbe(uint32_t) {}

static void waitFor(std::atomic<int> &count, int target, HANDLE event) {
	ULONGLONG deadline = GetTickCount64() + 10000;
	while (count.load() < target) {
		require(GetTickCount64() < deadline, "completion timed out");
		require(WaitForSingleObject(event, 100) != WAIT_FAILED, "completion event failed");
	}
}

int main(int argc, char **argv) {
	if (argc != 2) return 2;
	require(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)), "main STA setup");
	host = GetCurrentThreadId();
	decodedWake = CreateEventW(nullptr, FALSE, FALSE, nullptr);
	downloadedWake = CreateEventW(nullptr, FALSE, FALSE, nullptr);
	require(decodedWake && downloadedWake, "process event setup");
	std::string fileUri = "file:///" + std::string(argv[1]);
	std::replace(fileUri.begin(), fileUri.end(), '\\', '/');
	ImageSize source = ImageHeaderSize(fileUri.c_str());
	require(source.error.empty() && source.width == 64 && source.height == 64, "valid64 fixture header");
	std::ifstream input(argv[1], std::ios::binary);
	std::string body((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
	require(input.is_open() && !input.bad() && !body.empty() && body.size() < 2 * 1024 * 1024, "fixture file setup");
	WSADATA startup;
	require(WSAStartup(MAKEWORD(2, 2), &startup) == 0, "Winsock setup");
	SOCKET listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	require(listener != INVALID_SOCKET, "loopback socket setup");
	sockaddr_in address{};
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	address.sin_port = 0;
	require(bind(listener, reinterpret_cast<sockaddr *>(&address), sizeof address) == 0 &&
		listen(listener, 1) == 0, "loopback listener setup");
	int size = sizeof address;
	require(getsockname(listener, reinterpret_cast<sockaddr *>(&address), &size) == 0,
		"loopback address setup");
	std::thread server([&] {
		SOCKET client = accept(listener, nullptr, nullptr);
		require(client != INVALID_SOCKET, "loopback accept");
		std::string request;
		char bytes[1024];
		while (request.find("\r\n\r\n") == std::string::npos) {
			int got = recv(client, bytes, sizeof bytes, 0);
			require(got > 0 && request.size() + (size_t)got <= 8192, "loopback request");
			request.append(bytes, (size_t)got);
		}
		require(request.rfind("GET ", 0) == 0, "metadata request must GET fixture");
		std::string response = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: " +
			std::to_string(body.size()) + "\r\nConnection: close\r\n\r\n" + body;
		for (size_t sent = 0; sent < response.size();) {
			int count = send(client, response.data() + sent, (int)(response.size() - sent), 0);
			require(count > 0, "loopback response");
			sent += (size_t)count;
		}
		shutdown(client, SD_SEND);
		closesocket(client);
		closesocket(listener);
	});
	std::string url = "http://127.0.0.1:" + std::to_string(ntohs(address.sin_port)) +
		"/fixture.png?request=" + std::to_string(GetCurrentProcessId()) + "-" + std::to_string(GetTickCount64());
	ImageDecodeQueue first(postDecoded), second(postDecoded);
	uint32_t pixelA = first.Submit(fileUri.c_str());
	uint32_t pixelB = second.Submit(fileUri.c_str());
	uint32_t metadata = ImageFetch(url.c_str());
	waitFor(decoded, 2, decodedWake);
	waitFor(downloaded, 1, downloadedWake);
	auto a = first.Take();
	auto b = second.Take();
	auto files = ImageTakeDownloads();
	require(a.size() == 1 && b.size() == 1 && a[0].id == pixelA && b[0].id == pixelB &&
		a[0].error.empty() && b[0].error.empty() && a[0].pixels && b[0].pixels,
		"pixel completions valid and matching");
	require(files.size() == 1 && files[0].id == metadata && files[0].error.empty() &&
		!files[0].path.empty(), "metadata download valid and matching");
	ImageSize measured = ImageHeaderSizeOfFile(files[0].path);
	require(measured.error.empty() && measured.width == 64 && measured.height == 64 &&
		probes.load() == 2 && !wrongApartment.load(), "metadata header must not full-pixel decode");
	server.join();
	first.Close(); second.Close();
	printf("image-id setup pixel64/pixel64/metadata64 probes=%d ids=%u,%u,%u\n",
		probes.load(), pixelA, pixelB, metadata);
	fflush(stdout);
	require(pixelA != 0 && pixelB != 0 && metadata != 0 && pixelA != pixelB &&
		pixelA != metadata && pixelB != metadata, "request IDs collide across pixel and metadata producers");
	printf("image-id domains/header-only delivery passed\n");
	return 0;
}
