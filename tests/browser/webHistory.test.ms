import { Accessor } from "../../src/core/signal";
import { sleepAsync } from "std/core/promise";
import { createBrowserRoutingHistory } from "../../src/platform/browser/routingHistory";
import {
	ChildPages,
	ChildStack,
	NavigationChild,
	Pages,
	RoutePlan,
	RoutingError,
	RoutingRegistry,
	WebKeySerializer,
	WebNavigationError,
	WebNavigationOwner,
	childPagesWebNavigation,
	childStackWebNavigation,
	createChildPages,
	createChildStack,
	createRoutingSession,
	createWebHistory,
	webNavigationNode,
} from "../../src/navigation/index";

interface Section {
	pages: ChildPages<string, string> | null;
	web: WebNavigationOwner | null;
}

interface Gate {
	allowed: boolean;
}

function plain(): WebKeySerializer<string> {
	return {
		encode: (value: string): string => value,
		decode: (text: string): Result<string, WebNavigationError> => Result.ok(text),
	};
}

function nameKey(name: string): string {
	return name;
}

function pageInstance(configuration: Accessor<string>, active: Accessor<boolean>): string {
	return configuration();
}

function section(configuration: Accessor<string>, active: Accessor<boolean>): Section {
	if (configuration() !== "tabs") { return { pages: null, web: null }; }
	const pages = createChildPages<string, string>(
		{ items: ["feed", "inbox"], selectedIndex: 0 }, nameKey, pageInstance,
	);
	const web = childPagesWebNavigation<string, string>(pages, plain(), {
		pathMapper: (current: ChildPages<string, string>): string | null => {
			const selected = current.selected();
			if (selected === null) { return null; }
			return (selected as NavigationChild<string, string>).configuration();
		},
	});
	return { pages, web: { webNavigation: webNavigationNode<Pages<string>>(web) } };
}

function names(stack: ChildStack<string, Section>): string {
	return stack.configurations().join(",");
}

function pagesOf(stack: ChildStack<string, Section>): ChildPages<string, string> {
	return stack.items()[0].instance.pages as ChildPages<string, string>;
}

function selectedPage(stack: ChildStack<string, Section>): string {
	const selected = pagesOf(stack).selected();
	if (selected === null) { return "-"; }
	return (selected as NavigationChild<string, string>).configuration();
}

test "a stack holding pages mirrors into real browser history and follows back and forward" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/tabs", state: "" });
	const gate: Gate = { allowed: true };
	const stack = createChildStack<string, Section>(["tabs"], nameKey, section);
	const node = webNavigationNode<string>(childStackWebNavigation<string, Section>(stack, plain(), {
		pathMapper: (child: NavigationChild<string, Section>): string | null => child.configuration(),
		onBeforeNavigate: (): boolean => gate.allowed,
		childSelector: (child: NavigationChild<string, Section>): WebNavigationOwner | null => {
			return child.instance.web;
		},
	}));
	const web = createWebHistory(
		"main",
		node,
		(address: string | null): Result<RoutePlan, RoutingError> => {
			if (address === null || !(address as string).startsWith("/tabs")) {
				return Result.err(RoutingError.NoMatch);
			}
			return Result.ok({ commit: (): void => {
				stack.navigate((current: string[]): string[] => ["tabs"]);
			} });
		},
	);
	const registry = new RoutingRegistry("main");
	registry.register(web.participant);
	const errors: RoutingError[] = [];
	const created = createRoutingSession(registry, history, (failure: RoutingError): void => {
		errors.push(failure);
	});
	assert created.ok;
	if (created.ok) {
		const session = created.value;
		const stop = web.enable(session);
		try {
			assert history.read().url === "/tabs/feed", history.read().url;
			assert session.index() === 0, session.index().toString();
			pagesOf(stack).select(1);
			assert history.read().url === "/tabs/inbox", history.read().url;
			assert session.index() === 0, session.index().toString();
			stack.push("detail");
			assert history.read().url === "/detail", history.read().url;
			assert session.index() === 1, session.index().toString();

			assert history.go(-1);
			await sleepAsync(100);
			assert names(stack) === "tabs", names(stack);
			assert history.read().url === "/tabs/inbox", history.read().url;
			assert history.go(1);
			await sleepAsync(100);
			assert names(stack) === "tabs,detail", names(stack);
			assert history.read().url === "/detail", history.read().url;

			gate.allowed = false;
			assert history.go(-1);
			await sleepAsync(200);
			assert history.read().url === "/detail", "a refusal returns the browser: " +
				history.read().url;
			assert session.index() === 1, session.index().toString();
			assert names(stack) === "tabs,detail", names(stack);
			gate.allowed = true;

			assert stack.pop();
			await sleepAsync(100);
			assert history.read().url === "/tabs/inbox", history.read().url;
			assert session.index() === 0, session.index().toString();

			pagesOf(stack).select(0);
			assert history.read().url === "/tabs/feed", history.read().url;
			assert session.index() === 0, session.index().toString();
			assert history.go(1);
			await sleepAsync(100);
			assert names(stack) === "tabs,detail", names(stack);
			assert selectedPage(stack) === "inbox", selectedPage(stack);
			assert history.read().url === "/detail", history.read().url;
			assert errors.length === 0, errors.length.toString();
		} finally {
			stop();
			session.dispose();
			history.replace(original);
		}
	}
}
