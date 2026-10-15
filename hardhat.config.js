require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** Configuração Hardhat — River Token */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: { optimizer: { enabled: true, runs: 200 }, evmVersion: "cancun" },
  },
  networks: {
    hardhat: {},
    // Rede de teste pública (o professor pediu "tudo na testnet").
    // Preencha SEPOLIA_RPC_URL e PRIVATE_KEY no arquivo .env (veja .env.example).
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
  },
};
