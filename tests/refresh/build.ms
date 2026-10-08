// Neon Refresh fixture: the module pass is named here and runs under -d:refresh (tests/refresh/run.sh)
const config = {
	fmt: { useTabs: true },
	globalImports: [{ from: "../../src/converters", modulePass: "refreshPass" }],
};
export default config;
