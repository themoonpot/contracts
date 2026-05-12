import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TMPOnlySystem = buildModule("TMPOnlySystem", (m) => {
  const tmp = m.contract("MoonpotToken");
  return { tmp };
});

export default TMPOnlySystem;
