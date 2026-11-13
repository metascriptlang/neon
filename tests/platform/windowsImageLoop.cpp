#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <objbase.h>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <thread>
#include "windowsImageLoop.h"

static DWORD host;
static SOCKET listener = INVALID_SOCKET;
static std::thread server;
static std::string metadataUri, pictureUri;
static std::atomic<int> requests{0}, decodes{0}, hostDecodes{0};
static std::atomic<bool> wrongApartment{false};
static int wakes, reports;

static void require(bool ok, const char *message) {
	if (!ok) {
		fprintf(stderr, "image-loop assertion: %s\n", message);
		fflush(stderr);
		_Exit(1);
	}
}

static std::string read(const char *path) {
	std::ifstream input(path, std::ios::binary);
	std::string body((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
	require(input.is_open() && !input.bad() && !body.empty(), "PNG fixture setup");
	return body;
}

extern "C" const char *imageLoopStart(void) {
	host = GetCurrentThreadId();
	WSADATA startup;
	require(WSAStartup(MAKEWORD(2, 2), &startup) == 0, "Winsock setup");
	listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	require(listener != INVALID_SOCKET, "loopback socket setup");
	sockaddr_in address{};
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	require(bind(listener, reinterpret_cast<sockaddr *>(&address), sizeof address) == 0 &&
		listen(listener, 2) == 0, "loopback listener setup");
	int size = sizeof address;
	require(getsockname(listener, reinterpret_cast<sockaddr *>(&address), &size) == 0,
		"loopback address setup");
	std::string prefix = "http://127.0.0.1:" + std::to_string(ntohs(address.sin_port));
	metadataUri = prefix + "/metadata-" + std::to_string(GetCurrentProcessId()) + ".png";
	pictureUri = prefix + "/picture-" + std::to_string(GetCurrentProcessId()) + ".png";
	std::string metadata = read("examples/windowsNative/wide.png");
	std::string picture = read("examples/windowsNative/split.png");
	server = std::thread([metadata, picture] {
		for (int i = 0; i < 2; i++) {
			SOCKET client = accept(listener, nullptr, nullptr);
			require(client != INVALID_SOCKET, "loopback accept");
			std::string request;
			char bytes[1024];
			while (request.find("\r\n\r\n") == std::string::npos) {
				int got = recv(client, bytes, sizeof bytes, 0);
				require(got > 0 && request.size() + (size_t)got <= 8192, "loopback request");
				request.append(bytes, (size_t)got);
			}
			bool isMetadata = request.rfind("GET /metadata-", 0) == 0;
			require(isMetadata || request.rfind("GET /picture-", 0) == 0, "unexpected HTTP route");
			const std::string &body = isMetadata ? metadata : picture;
			std::string response = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nCache-Control: no-store\r\nContent-Length: " +
				std::to_string(body.size()) + "\r\nConnection: close\r\n\r\n" + body;
			for (size_t sent = 0; sent < response.size();) {
				int count = send(client, response.data() + sent, (int)(response.size() - sent), 0);
				require(count > 0, "loopback response");
				sent += (size_t)count;
			}
			shutdown(client, SD_SEND);
			closesocket(client);
			requests.fetch_add(1);
		}
	});
	return metadataUri.c_str();
}

extern "C" const char *imageLoopPictureUri(void) { return pictureUri.c_str(); }

extern "C" void imageWorkerDecodeProbe(void) {
	decodes.fetch_add(1);
	if (GetCurrentThreadId() == host) hostDecodes.fetch_add(1);
	else {
		APTTYPE type;
		APTTYPEQUALIFIER qualifier;
		if (FAILED(CoGetApartmentType(&type, &qualifier)) || type != APTTYPE_MTA)
			wrongApartment.store(true);
	}
}

extern "C" void imageDecodeJobDoneProbe(uint32_t) {}

extern "C" void imageLoopOnWake(void) {
	require(GetCurrentThreadId() == host, "Ion wake not on host thread");
	wakes++;
}

extern "C" void imageLoopOnReport(void) {
	require(GetCurrentThreadId() == host, "image report not on host thread");
	reports++;
}

extern "C" int32_t imageLoopFinish(void) {
	require(GetCurrentThreadId() == host, "finish not on host thread");
	require(requests.load() == 2 && wakes > 0 && reports == 2,
		"real HTTP/Ion wake/two main reports did not complete");
	server.join();
	closesocket(listener);
	WSACleanup();
	printf("image-loop routing passed: requests=%d Ion-wakes=%d main-reports=%d decodes=%d host-decodes=%d\n",
		requests.load(), wakes, reports, decodes.load(), hostDecodes.load());
	fflush(stdout);
	require(decodes.load() == 1 && !wrongApartment.load(), "metadata performed pixel decode or wrong worker apartment");
	require(hostDecodes.load() == 0, "pixel decode ran on host thread");
	return 0;
}
