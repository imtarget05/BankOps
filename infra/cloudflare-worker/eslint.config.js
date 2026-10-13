import tsParser from "@typescript-eslint/parser";

export default [
  {
    files: ["src/**/*.ts"],
    languageOptions: {
      parser: tsParser,
      parserOptions: { ecmaVersion: "latest", sourceType: "module" },
    },
    rules: {
      "no-constant-condition": "error",
      "no-debugger": "error",
      "no-duplicate-imports": "error",
    },
  },
];
