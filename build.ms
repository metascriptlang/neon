// Neon Build Configuration
const config = {
	fmt: { useTabs: true },
	globalImports: ["./src/converters"],
	deps: {
		"pulse": "file:../pulse",
	},
};
export default config;
