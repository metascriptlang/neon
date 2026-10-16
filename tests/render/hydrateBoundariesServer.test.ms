import { renderToMarkup } from "../../src/render/ssr";
import { loadingApp, loadingHtml } from "../browser/boundaryPages";

test "the server writes the page the Chrome hydration test of Loading starts from" {
	assert renderToMarkup(loadingApp()).html === loadingHtml, renderToMarkup(loadingApp()).html;
}
