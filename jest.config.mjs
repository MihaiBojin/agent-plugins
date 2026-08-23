/** @type {import('jest').Config} */
export default {
  testEnvironment: "node",
  clearMocks: true,
  // The tooling is plain ESM with no types to strip, and so are its tests:
  // no transform, just node's own module loader.
  testMatch: ["**/__tests__/**/*.test.mjs"],
  transform: {},
};
