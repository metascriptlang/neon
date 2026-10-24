import { Accessor, Signal, accessor } from "../core/signal";
import { replyOf } from "./route";
import { Router, SubmissionBase, useRouter } from "./router";
import { revalidate } from "./data";

const ACTION_URL = "https://action/";

class Outcome<R> {
	value: R | null;
	failure: Error | null;

	constructor(value: R | null, failure: Error | null) {
		this.value = value;
		this.failure = failure;
	}
}

class Retry<R> {
	promise: Promise<R | null>;

	constructor(promise: Promise<R | null>) {
		this.promise = promise;
	}
}

export class Submission<I, R> extends SubmissionBase {
	input: I;
	router: Router;
	run: (sub: Submission<I, R>) => Promise<R | null>;
	outcome: Signal<Outcome<R> | null> = new Signal<Outcome<R> | null>(null);
	origin: Submission<I, R> | null = null;
	retried: Retry<R> | null = null;

	constructor(input: I, url: string, router: Router, run: (sub: Submission<I, R>) => Promise<R | null>) {
		super(url);
		this.input = input;
		this.router = router;
		this.run = run;
	}

	pending(): boolean {
		return this.outcome.get() === null;
	}

	result(): R | null {
		const outcome = this.outcome.get();
		return outcome === null ? null : outcome.value;
	}

	error(): Error | null {
		const outcome = this.outcome.get();
		return outcome === null ? null : outcome.failure;
	}

	clear(): void {
		const target = this.origin ?? this;
		this.router.submissions.set(this.router.submissions.peek().filter((held: SubmissionBase): boolean => held !== target));
	}

	retry(): Promise<R | null> {
		const origin = this.origin;
		if (origin !== null) {
			const again = origin.retry();
			this.retried = new Retry<R>(again);
			return again;
		}
		this.outcome.set(null);
		return this.run(this);
	}
}

export interface ActionOptions<I, R> {
	name: string;
	onComplete?: ((submission: Submission<I, R>) => void) | null;
}

export class Action<I, R> {
	url: string;
	fn: (input: I) => Promise<R>;
	onComplete: ((submission: Submission<I, R>) => void) | null;

	constructor(url: string, fn: (input: I) => Promise<R>, onComplete: ((submission: Submission<I, R>) => void) | null) {
		this.url = url;
		this.fn = fn;
		this.onComplete = onComplete;
	}
}

export function action<I, R>(fn: (input: I) => Promise<R>, name: string): Action<I, R> {
	return new Action<I, R>(ACTION_URL + name, fn, null);
}

export function action<I, R>(fn: (input: I) => Promise<R>, options: ActionOptions<I, R>): Action<I, R> {
	return new Action<I, R>(ACTION_URL + options.name, fn, options.onComplete ?? null);
}

function landed<I, R>(sub: Submission<I, R>, value: R | null, failure: Error | null): Outcome<R> | null {
	const reply = failure === null ? null : replyOf(failure);
	if (failure !== null && reply === null) { return new Outcome<R>(null, failure); }
	let keys: string[] | null = null;
	if (reply !== null) {
		keys = reply.revalidate;
		sub.router.deliver(reply, false);
	}
	if (keys === null) { revalidate(); } else { revalidate(keys as string[]); }
	return reply !== null || value === null ? null : new Outcome<R>(value, null);
}

async function settle<I, R>(act: Action<I, R>, sub: Submission<I, R>, call: Promise<R>): Promise<R | null> {
	let value: R | null = null;
	let failure: Error | null = null;
	try {
		value = await call;
	} catch (caught) {
		failure = caught;
	}
	const result = landed<I, R>(sub, value, failure);
	const complete = act.onComplete;
	if (complete !== null) {
		const copy = new Submission<I, R>(sub.input, sub.url, sub.router, sub.run);
		copy.origin = sub;
		copy.outcome = new Signal<Outcome<R> | null>(result === null ? new Outcome<R>(null, null) : result);
		(complete as (submission: Submission<I, R>) => void)(copy);
		const again = copy.retried;
		if (again !== null) { return await again.promise; }
	}
	if (result === null) {
		sub.clear();
		// Parked on ~/metascript/.inbox/compiler/2026-10-08-async-return-null-literal-refused.md: `return null;` in place of this typed constant.
		const none: R | null = null;
		return none;
	}
	sub.outcome.set(result);
	if (result.failure !== null) { throw result.failure; }
	return result.value;
}

export function useAction<I, R>(act: Action<I, R>): (input: I) => Promise<R | null> {
	const router = useRouter("useAction");
	return (input: I): Promise<R | null> => {
		const sub = new Submission<I, R>(
			input,
			act.url,
			router,
			(again: Submission<I, R>): Promise<R | null> => settle<I, R>(act, again, act.fn(input)),
		);
		router.submissions.set(router.submissions.peek().concat([sub]));
		return sub.retry();
	};
}

function submissionsOf<I, R>(act: Action<I, R>, filter: ((input: I) => boolean) | null, caller: string): Accessor<Submission<I, R>[]> {
	const router = useRouter(caller);
	return accessor((): Submission<I, R>[] => {
		const found: Submission<I, R>[] = [];
		for (const held of router.submissions.get()) {
			if (held.url !== act.url) { continue; }
			const sub = held as Submission<I, R>;
			if (filter === null || filter(sub.input)) { found.push(sub); }
		}
		return found;
	});
}

export function useSubmissions<I, R>(act: Action<I, R>, filter: ((input: I) => boolean) | null = null): Accessor<Submission<I, R>[]> {
	return submissionsOf<I, R>(act, filter, "useSubmissions");
}

export function useSubmission<I, R>(act: Action<I, R>, filter: ((input: I) => boolean) | null = null): Accessor<Submission<I, R> | null> {
	const found = submissionsOf<I, R>(act, filter, "useSubmission");
	return accessor((): Submission<I, R> | null => {
		const subs = found();
		return subs.length === 0 ? null : subs[subs.length - 1];
	});
}
