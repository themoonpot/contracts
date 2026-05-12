import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const MockOnly = buildModule("MockOnly", (m) => {
  const vrf = m.contract("DeployableVRFCoordinatorV2_5Mock", [
    25n * 10n ** 16n,
    1_000_000_000n,
    1_000_000_000_000_000n,
  ]);
  m.call(vrf, "createSubscription", []);
  return { vrf };
});
export default MockOnly;
