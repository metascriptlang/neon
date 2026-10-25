import { createStyles, styleOf, createBreakpoints } from "../../src/macros/ui/style";

let w = 900;
const screen = createBreakpoints({ wide: w });
const sheet = createStyles({ side: { width: "100%", when: { [screen.wide]: { width: 280 } } } });
console.log(sheet.side.width);
