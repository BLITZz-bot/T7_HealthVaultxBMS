require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      // "paris" is safe for MST EVM — avoids PUSH0 opcode issues.
      // Change to "cancun" only if MST confirms Cancun support.
      evmVersion: "paris",
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    // Local Hardhat node for fast unit tests
    hardhat: {
      chainId: 31337,
    },
    // MST Testnet — REAL deployment target
    mstTestnet: {
      url: "https://testnetrpc.mstblockchain.com",
      chainId: 91562037,   // verified: 0x5752035
      accounts: process.env.DEPLOYER_PRIVATE_KEY
        ? [process.env.DEPLOYER_PRIVATE_KEY]
        : [],
      gasPrice: "auto",
      timeout: 120000,     // 2 min timeout for slower testnet blocks
    },
  },
  paths: {
    sources:   "./contracts",
    tests:     "./test",
    cache:     "./cache",
    artifacts: "./artifacts",
  },
  // For etherscan-style verification on MSTScan if they support it
  etherscan: {
    apiKey: {
      mstTestnet: process.env.MSTSCAN_API_KEY || "no-key",
    },
    customChains: [
      {
        network: "mstTestnet",
        chainId: 91562037,
        urls: {
          apiURL:    "https://mstscan.com/api",
          browserURL:"https://mstscan.com",
        },
      },
    ],
  },
};
