import hardhatContractSizer from "@solidstate/hardhat-contract-sizer";
import hardhatFoundry from "@nomicfoundation/hardhat-foundry";
import hardhatKeystore from "@nomicfoundation/hardhat-keystore";
import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import hardhatVerify from "@nomicfoundation/hardhat-verify";
import type { HardhatUserConfig } from "hardhat/config";
import { configVariable } from "hardhat/config";

const config: HardhatUserConfig = {
  plugins: [
    hardhatContractSizer,
    hardhatFoundry,
    hardhatKeystore,
    hardhatToolboxViemPlugin,
    hardhatVerify,
  ],
  ignition: {
    blockPollingInterval: 20_000,
    maxFeeBumps: 5,
    timeBeforeBumpingFees: 120_000,
    strategyConfig: {
      create2: {
        salt: "0x000000000000000000000000000000000000000000000000000000000000615f",
      },
    },
  },
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
        settings: {
          metadata: {
            bytecodeHash: "none",
          },
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true,
        },
      },
      production: {
        version: "0.8.28",
        settings: {
          metadata: {
            bytecodeHash: "none",
          },
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true,
        },
      },
    },
  },
  networks: {
    localhost: {
      chainId: 31337,
      type: "http",
      url: "http://127.0.0.1:8545",
    },
    base: {
      type: "http",
      url: configVariable("BASE_RPC_URL"),
      accounts: [configVariable("WALLET_PRIVATE_KEY")],
    },
  },
  verify: {
    blockscout: {
      enabled: false,
    },
    etherscan: {
      apiKey: configVariable("ETHERSCAN_API_KEY"),
    },
  },
  contractSizer: {
    alphaSort: false,
    runOnCompile: false,
    flat: false,
    strict: false,
    only: [],
    except: [],
    unit: "KiB",
  },
};

export default config;
