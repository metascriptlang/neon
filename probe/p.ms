
function take<U>(xs: U[]): U { return xs[0]; }
function main(): void { const r = take<() => number>([() => 7]); console.log(r().toString()); }

