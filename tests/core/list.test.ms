import { createList, listInsert, listMove, listRemove, listSet } from "../../src/core/list";
import { createRoot } from "../../src/core/owner";
import { createEffect } from "../../src/core/effect";

test "createList reads its items through read, length and at" {
	const l = createList<number>([1, 2, 3]);
	assert l.length() === 3, "length 3";
	assert l.at(0) === 1, "at 0";
	assert l.at(2) === 3, "at 2";
	const xs = l.read();
	assert xs.length === 3 && xs[1] === 2, "read gives the items";
}

test "push writes one insert op at the tail" {
	const l = createList<number>([1, 2]);
	const q = l.attach();
	l.push(3);
	assert q.ops.length === 1, "one op";
	assert q.ops[0].kind === listInsert, "kind insert";
	assert q.ops[0].a === 2, "at the tail";
	assert q.ops[0].v === 3, "carries the value";
	assert l.length() === 3 && l.at(2) === 3, "the array holds it";
}

test "insert shifts the array and names the slot it wrote" {
	const l = createList<number>([1, 2, 3]);
	const q = l.attach();
	l.insert(1, 9);
	assert q.ops[0].kind === listInsert && q.ops[0].a === 1 && q.ops[0].v === 9, "insert at 1";
	assert l.length() === 4, "length 4";
	assert l.at(0) === 1 && l.at(1) === 9 && l.at(2) === 2 && l.at(3) === 3, "shifted right of 1";
	l.insert(4, 7);
	assert l.at(4) === 7, "insert at the length appends";
}

test "remove shifts the array and carries the item that left" {
	const l = createList<number>([1, 2, 3]);
	const q = l.attach();
	l.remove(0);
	assert q.ops[0].kind === listRemove && q.ops[0].a === 0 && q.ops[0].v === 1, "remove 0 carries 1";
	assert l.length() === 2 && l.at(0) === 2 && l.at(1) === 3, "shifted left";
}

test "move rotates one item in both directions" {
	const l = createList<number>([1, 2, 3, 4]);
	const q = l.attach();
	l.move(0, 2);
	assert q.ops[0].kind === listMove && q.ops[0].a === 0 && q.ops[0].b === 2, "move 0 to 2";
	assert l.at(0) === 2 && l.at(1) === 3 && l.at(2) === 1 && l.at(3) === 4, "forward move";
	l.move(3, 1);
	assert l.at(0) === 2 && l.at(1) === 4 && l.at(2) === 3 && l.at(3) === 1, "backward move";
	l.move(2, 2);
	assert q.ops.length === 2, "a move to its own slot writes no op";
}

test "set writes the value and one set op" {
	const l = createList<number>([1, 2]);
	const q = l.attach();
	l.set(1, 5);
	assert q.ops[0].kind === listSet && q.ops[0].a === 1 && q.ops[0].v === 5, "set at 1";
	assert l.at(1) === 5, "the array holds it";
}

test "replaceAll drops the queued ops and asks for a reset" {
	const l = createList<number>([1, 2]);
	const q = l.attach();
	l.push(3);
	l.replaceAll([7, 8, 9, 10]);
	assert q.ops.length === 0, "the ops before the reset are gone";
	assert q.reset, "the queue asks for a reset";
	assert l.length() === 4 && l.at(0) === 7, "the array is the new one";
	l.push(11);
	assert q.ops.length === 1 && q.reset, "an op after the reset queues behind the flag";
}

test "every command bumps the version once" {
	createRoot((d) => {
		const l = createList<number>([1]);
		let runs = 0;
		createEffect(() => { l.length(); runs = runs + 1; });
		assert runs === 1, "the effect ran once";
		l.push(2);
		assert runs === 2, "push";
		l.insert(0, 0);
		assert runs === 3, "insert";
		l.move(0, 1);
		assert runs === 4, "move";
		l.set(0, 4);
		assert runs === 5, "set";
		l.remove(0);
		assert runs === 6, "remove";
		l.replaceAll([1, 2]);
		assert runs === 7, "replaceAll";
		d();
	});
}

test "two consumers each get every op" {
	const l = createList<number>([1]);
	const a = l.attach();
	const b = l.attach();
	l.push(2);
	assert a.ops.length === 1 && b.ops.length === 1, "both queues hold the op";
	l.detach(a);
	l.push(3);
	assert a.ops.length === 1, "a detached queue stops receiving";
	assert b.ops.length === 2, "the live queue keeps receiving";
}

test "an index outside the list raises and names the index" {
	const l = createList<number>([1, 2]);
	let caught = "";
	try { l.at(2); } catch (e) { caught = e.toString(); }
	assert caught.includes("2"), "at names the index: " + caught;
	caught = "";
	try { l.remove(5); } catch (e) { caught = e.toString(); }
	assert caught.includes("remove"), "remove names itself: " + caught;
	caught = "";
	try { l.insert(3, 0); } catch (e) { caught = e.toString(); }
	assert caught.includes("insert"), "insert past the length raises: " + caught;
}

test "detaching a queue twice raises" {
	const l = createList<number>([1]);
	const q = l.attach();
	l.detach(q);
	let caught = "";
	try { l.detach(q); } catch (e) { caught = e.toString(); }
	assert caught !== "", "the second detach raises";
}
