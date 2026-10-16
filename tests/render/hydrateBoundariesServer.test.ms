import { renderToMarkup } from "../../src/render/ssr";
import { loadingApp, loadingHtml, loadingIdsApp, loadingIdsMarkup } from "../browser/boundaryPages";

test "the server writes the page the Chrome hydration test of Loading starts from" {
	assert renderToMarkup(loadingApp()).html === loadingHtml, renderToMarkup(loadingApp()).html;
}

test "a Loading on the server draws the owner ids the client draws for the same tree" {
	assert renderToMarkup(loadingIdsApp()).html === loadingIdsMarkup, renderToMarkup(loadingIdsApp()).html;
}
