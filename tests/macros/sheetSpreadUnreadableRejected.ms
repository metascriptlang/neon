import { createStyles, styleOf } from "../../src/macros/ui/style";
import { Style } from "../../src/render/style";

let base: Style = { width: 10 };
const sheet = createStyles({ box: { ...base, height: 4 } });
console.log(sheet.box.height);
