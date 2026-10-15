const hre = require("hardhat");

/**
 * Deploy do River Token na rede escolhida.
 * Local:   npx hardhat run scripts/deploy.js
 * Sepolia: npx hardhat run scripts/deploy.js --network sepolia
 *
 * Implanta as DUAS arquiteturas para comparação:
 *   (A) RiverDAO1155           — DAO completa unificada em ERC-1155
 *   (B) RiverIdentidade721 + RiverToken20 — equivalente dividido
 */
async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deployer:", deployer.address);

  // (A) Unificado — ERC-1155
  const DAO = await hre.ethers.getContractFactory("RiverDAO1155");
  const dao = await DAO.deploy();
  await dao.waitForDeployment();
  console.log("RiverDAO1155 (unificado):", await dao.getAddress());

  // (B) Dividido — ERC-721 (identidade) + ERC-20 (governança)
  const ID = await hre.ethers.getContractFactory("RiverIdentidade721");
  const id = await ID.deploy();
  await id.waitForDeployment();
  console.log("RiverIdentidade721:", await id.getAddress());

  const TK = await hre.ethers.getContractFactory("RiverToken20");
  const tk = await TK.deploy(await id.getAddress());
  await tk.waitForDeployment();
  console.log("RiverToken20:", await tk.getAddress());

  // Liga o ERC-20 ao ERC-721 de identidade (uma única vez).
  await (await id.definirDAO(await tk.getAddress())).wait();
  console.log("Vinculo 721 <- 20 definido.");

  // Exemplo opcional: carência de 1 dia antes de votar (anti flash-buy).
  // await (await dao.setCooldownVoto(24 * 60 * 60)).wait();
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
