import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const MockUSDCOnly = buildModule("MockUSDCOnly", (m) => {
  const musdc = m.contract("MockUSDC");
  return { musdc };
});

export default MockUSDCOnly;
