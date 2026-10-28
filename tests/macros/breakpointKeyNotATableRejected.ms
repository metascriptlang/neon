import { createStyles, styleOf } from "../../src/macros/ui/style";

const screen = { wide: 900 };
const sheet = createStyles({ side: { width: "100%", when: { [screen.wide]: { width: 280 } } } });
console.log(sheet.side.width);
