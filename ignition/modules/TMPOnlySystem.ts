import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Deploy mode. `MOONPOT_MODE=mock` deploys the test token — unrelated
// name/symbol ("Test Token" / "TST") and a distinct contract name (MockToken)
// so a mock deploy can never be mistaken for real TMP. Anything else (including
// unset) deploys the production token.
const MOCK = (process.env.MOONPOT_MODE ?? "production").toLowerCase() === "mock";

const TMPOnlySystem = buildModule("TMPOnlySystem", (m) => {
  const tmp = m.contract(MOCK ? "MockToken" : "MoonpotToken", [], {
    id: "TMP",
  });
  return { tmp };
});

export default TMPOnlySystem;
