import { Accessor, Signal, accessor } from "../core/signal";
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

class SubmissionBase {
	url: string;

	constructor(url: string) {
		this.url = url;
	}
}

const submissions = new Signal<SubmissionBase[]>([]);

export class Submission<I, R> extends SubmissionBase {
	input: I;
	run: (input: I) => Promise<R>;
	outcome: Signal<Outcome<R> | null> = new Signal<Outcome<R> | null>(null);

	constructor(input: I, url: string, run: (input: I) => Promise<R>) {
		super(url);
		this.input = input;
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
		submissions.set(submissions.peek().filter((held: SubmissionBase): boolean => held !== this));
	}

	retry(): Promise<R> {
		this.outcome.set(null);
		return settle<I, R>(this, this.run(this.input));
	}
}

async function settle<I, R>(sub: Submission<I, R>, call: Promise<R>): Promise<R> {
	let value: R;
	try {
		value = await call;
	} catch (failure) {
		sub.outcome.set(new Outcome<R>(null, failure));
		throw failure;
	}
	revalidate();
	if (value === null) {
		sub.clear();
		return value;
	}
	sub.outcome.set(new Outcome<R>(value, null));
	return value;
}

export class Action<I, R> {
	url: string;
	fn: (input: I) => Promise<R>;

	constructor(url: string, fn: (input: I) => Promise<R>) {
		this.url = url;
		this.fn = fn;
	}
}

export function action<I, R>(fn: (input: I) => Promise<R>, name: string): Action<I, R> {
	return new Action<I, R>(ACTION_URL + name, fn);
}

export function useAction<I, R>(act: Action<I, R>): (input: I) => Promise<R> {
	return (input: I): Promise<R> => {
		const sub = new Submission<I, R>(input, act.url, act.fn);
		submissions.set(submissions.peek().concat([sub]));
		return settle<I, R>(sub, act.fn(input));
	};
}

export function useSubmissions<I, R>(act: Action<I, R>, filter: ((input: I) => boolean) | null = null): Accessor<Submission<I, R>[]> {
	return accessor((): Submission<I, R>[] => {
		const found: Submission<I, R>[] = [];
		for (const held of submissions.get()) {
			if (held.url !== act.url) { continue; }
			const sub = held as Submission<I, R>;
			if (filter === null || filter(sub.input)) { found.push(sub); }
		}
		return found;
	});
}

export function useSubmission<I, R>(act: Action<I, R>, filter: ((input: I) => boolean) | null = null): Accessor<Submission<I, R> | null> {
	const found = useSubmissions<I, R>(act, filter);
	return accessor((): Submission<I, R> | null => {
		const subs = found();
		return subs.length === 0 ? null : subs[subs.length - 1];
	});
}
