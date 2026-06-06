import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// `MOONPOT_MODE=mock` deploys MockMoonpotHook (same logic + permission flags,
// distinct contract name). Must match the artifact used to mine the salt.
const MOCK = (process.env.MOONPOT_MODE ?? "production").toLowerCase() === "mock";

const HookOnlySystem = buildModule("HookOnlySystem", (m) => {
  const poolManager = m.getParameter("poolManager");
  const positionManager = m.getParameter("positionManager");
  const permit2 = m.getParameter("permit2");
  const usdc = m.getParameter("usdc");
  const tmp = m.getParameter("tmp");
  const owner = m.getParameter("owner");

  const hook = m.contract(
    MOCK ? "MockMoonpotHook" : "MoonpotHook",
    [poolManager, positionManager, permit2, usdc, tmp, owner],
    { id: "Hook" },
  );

  return { hook };
});

export default HookOnlySystem;
