import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Deploy mode. `MOONPOT_MODE=mock` deploys the test token — distinct
// name/symbol ("Moonpot Test Token" / "tTMP") and a distinct contract name
// (MockMoonpotToken) so a mock deploy can never be mistaken for real TMP.
// Anything else (including unset) deploys the production token.
const MOCK = (process.env.MOONPOT_MODE ?? "production").toLowerCase() === "mock";

const TMPOnlySystem = buildModule("TMPOnlySystem", (m) => {
  const tmp = m.contract(MOCK ? "MockMoonpotToken" : "MoonpotToken", [], {
    id: "TMP",
  });
  return { tmp };
});

export default TMPOnlySystem;
