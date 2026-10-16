import { renderToMarkup } from "../../src/render/ssr";
import { loadingApp, erroringApp, erroringChildApp, loadingHtml, erroringHtml, erroringChildHtml, loadingIdsApp, erroringIdsApp, loadingIdsMarkup, erroringIdsMarkup } from "../browser/boundaryPages";

test "the server writes the pages the Chrome hydration tests of Loading and Errored start from" {
	assert renderToMarkup(loadingApp()).html === loadingHtml, renderToMarkup(loadingApp()).html;
	assert renderToMarkup(erroringApp()).html === erroringHtml, renderToMarkup(erroringApp()).html;
	const html = renderToMarkup(erroringChildApp([0], [])).html;
	assert html === erroringChildHtml, html;
}

test "a Loading and an Errored on the server draw the owner ids the client draws for the same tree" {
	assert renderToMarkup(loadingIdsApp()).html === loadingIdsMarkup, renderToMarkup(loadingIdsApp()).html;
	assert renderToMarkup(erroringIdsApp()).html === erroringIdsMarkup, renderToMarkup(erroringIdsApp()).html;
}
