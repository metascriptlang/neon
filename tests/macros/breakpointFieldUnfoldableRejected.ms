import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createBreakpoints } from "../../src/render/breakpoints";

const screen = createBreakpoints({ wide: 900 });
let narrow = 280;
const sheet = createStyles({ side: { width: "100%", when: { [screen.wide]: { width: narrow } } } });
console.log(sheet.side.width);
