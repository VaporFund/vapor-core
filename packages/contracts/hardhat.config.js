/** @type import('hardhat/config').HardhatUserConfig */
require("@nomicfoundation/hardhat-toolbox");

require("dotenv").config()

const RPC_HOST = process.env.RPC_HOST

module.exports = {
  mocha: {
    timeout: 1200000,
  },
  solidity: {
    version: "0.8.13",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    },
  },
  networks: {
    hardhat: {
      chainId: 1,
      forking: {
        url: RPC_HOST,
        // blockNumber: 14390000
      }
    }
  }
  
};
