import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";
import "hardhat-deploy";
import "hardhat-deploy-ethers";
dotenv.config();

import "./src/tasks/codesize";

const ZG_TESTNET_NETWORK_NAME = process.env.ZG_TESTNET_NETWORK_NAME;
const ZG_MAINNET_NETWORK_NAME = process.env.ZG_MAINNET_NETWORK_NAME;
const ZG_TESTNET_RPC_URL = process.env.ZG_TESTNET_RPC_URL;
const ZG_MAINNET_RPC_URL = process.env.ZG_MAINNET_RPC_URL;
const ZG_TESTNET_CHAIN_ID = process.env.ZG_TESTNET_CHAIN_ID;
const ZG_MAINNET_CHAIN_ID = process.env.ZG_MAINNET_CHAIN_ID;
const ZG_TESTNET_PRIVATE_KEY = process.env.ZG_TESTNET_PRIVATE_KEY;
const ZG_MAINNET_PRIVATE_KEY = process.env.ZG_MAINNET_PRIVATE_KEY;
const ZG_TESTNET_ETHERSCAN_BROWSER_URL = process.env.ZG_TESTNET_ETHERSCAN_BROWSER_URL;
const ZG_TESTNET_ETHERSCAN_API_URL = process.env.ZG_TESTNET_ETHERSCAN_API_URL;
const ZG_MAINNET_ETHERSCAN_BROWSER_URL = process.env.ZG_MAINNET_ETHERSCAN_BROWSER_URL;
const ZG_MAINNET_ETHERSCAN_API_URL = process.env.ZG_MAINNET_ETHERSCAN_API_URL;
const LOCAL_DEPLOYMENTS_PATH = process.env.LOCAL_DEPLOYMENTS_PATH;
const ZG_TESTNET_DEPLOYMENTS_PATH = process.env.ZG_TESTNET_DEPLOYMENTS_PATH;
const ZG_MAINNET_DEPLOYMENTS_PATH = process.env.ZG_MAINNET_DEPLOYMENTS_PATH;

const config: HardhatUserConfig = {
  paths: {
    artifacts: "build/artifacts",
    cache: "build/cache",
    sources: "contracts",
    deploy: "scripts/deploy",
  },
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      allowBlocksWithSameTimestamp: true,
      blockGasLimit: 100000000,
      gas: 100000000,
      live: false,
      saveDeployments: true,
      tags: ["test", "local"]
    },
    zgTestnet: {
      url: ZG_TESTNET_RPC_URL || "",
      accounts: [ZG_TESTNET_PRIVATE_KEY || ""],
      chainId: Number(ZG_TESTNET_CHAIN_ID) || 16602,
      live: true,
      saveDeployments: true,
      tags: ["staging"],
      timeout: 120000, // 120 seconds timeout
      gasPrice: "auto"
    },
    zgMainnet: {
      url: ZG_MAINNET_RPC_URL || "",
      accounts: [ZG_MAINNET_PRIVATE_KEY || ""],
      chainId: Number(ZG_MAINNET_CHAIN_ID) || 16661,
      live: true,
      saveDeployments: true,
      tags: ["production"],
      timeout: 120000, // 120 seconds timeout
      gasPrice: "auto"
    },
  },
  etherscan: {
    apiKey: {
      zgTestnet: "00",
      zgMainnet: "00",
    },
    customChains: [
      {
        network: ZG_TESTNET_NETWORK_NAME || "zgTestnet",
        chainId: Number(ZG_TESTNET_CHAIN_ID) || 16602,
        urls: {
          apiURL: ZG_TESTNET_ETHERSCAN_API_URL || "",
          browserURL: ZG_TESTNET_ETHERSCAN_BROWSER_URL || "",
        },
      },
      {
        network: ZG_MAINNET_NETWORK_NAME || "zgMainnet",
        chainId: Number(ZG_MAINNET_CHAIN_ID) || 16661,
        urls: {
          apiURL: ZG_MAINNET_ETHERSCAN_API_URL || "",
          browserURL: ZG_MAINNET_ETHERSCAN_BROWSER_URL || "",
        },
      },
    ],
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  namedAccounts: {
    deployer: {
      default: 0,
      hardhat: 0,
      zgTestnet: 0,
    },
    creator: {
      default: 0,
      hardhat: 0,
      zgTestnet: 0,
    },
    alice: {
      default: 1,
      hardhat: 1,
    },
    bob: {
      default: 2,
      hardhat: 2,
    },
  },
  external: {
    contracts: [
      {
        artifacts: "build/artifacts",
      },
    ],
    deployments: {
      hardhat: [LOCAL_DEPLOYMENTS_PATH || "deployments/hardhat"],
      zgTestnet: [ZG_TESTNET_DEPLOYMENTS_PATH || "deployments/zgTestnet"],
      zgMainnet: [ZG_MAINNET_DEPLOYMENTS_PATH || "deployments/zgMainnet"],
    },
  },
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
  }
};

export default config;