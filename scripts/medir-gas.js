const hre = require("hardhat");
const fs = require("fs");
const { ethers } = hre;

/**
 * Mede o gas real de cada funcao e monta as tabelas do relatorio:
 *   - Tabela 4.2: custo por funcao do RiverToken
 *   - Tabela 4.5: comparacao ERC-20 vs ERC-721 vs ERC-1155
 * Roda em qualquer rede (local por padrao; identico em gas na Sepolia).
 *   npx hardhat run scripts/medir-gas.js
 */
async function gasDeChamada(promessa) {
  const tx = await promessa;
  const rcpt = await tx.wait();
  return Number(rcpt.gasUsed);
}
async function gasDeDeploy(contrato) {
  const rcpt = await contrato.deploymentTransaction().wait();
  return Number(rcpt.gasUsed);
}

async function main() {
  const [clube, torcedor, outro] = await ethers.getSigners();
  const linhasRVR = [];
  const comp = {}; // padrao -> {deploy, mint, transfer1, batch10}

  // ───────────────── RiverToken ($RVR) ─────────────────
  const RVR = await ethers.getContractFactory("RiverToken");
  const rvr = await RVR.deploy();
  await rvr.waitForDeployment();
  linhasRVR.push(["deploy", await gasDeDeploy(rvr)]);
  comp["ERC-20 ($RVR)"] = { deploy: await gasDeDeploy(rvr) };

  // comprar (0.1 ETH -> 1000 RVR com preco padrao 0.0001 ETH)
  linhasRVR.push(["comprar()", await gasDeChamada(
    rvr.connect(torcedor).comprar({ value: ethers.parseEther("0.1") }))]);
  comp["ERC-20 ($RVR)"].mint = await gasDeChamada(
    rvr.connect(outro).comprar({ value: ethers.parseEther("0.1") }));

  // transferencia unitaria
  comp["ERC-20 ($RVR)"].transfer1 = await gasDeChamada(
    rvr.connect(torcedor).transfer(outro.address, ethers.parseEther("1")));

  // governanca
  linhasRVR.push(["criarProposta()", await gasDeChamada(
    rvr.connect(clube).criarProposta("Novo uniforme 2026", 7 * 24 * 3600))]);
  linhasRVR.push(["votar()", await gasDeChamada(
    rvr.connect(torcedor).votar(0, true))]);

  // staking
  linhasRVR.push(["stake()", await gasDeChamada(
    rvr.connect(outro).stake(ethers.parseEther("100")))]);
  await hre.network.provider.send("evm_increaseTime", [30 * 24 * 3600]);
  await hre.network.provider.send("evm_mine", []);
  linhasRVR.push(["unstake()", await gasDeChamada(
    rvr.connect(outro).unstake(ethers.parseEther("100")))]);

  // encerrarProposta (avanca o tempo alem do prazo)
  await hre.network.provider.send("evm_increaseTime", [8 * 24 * 3600]);
  await hre.network.provider.send("evm_mine", []);
  linhasRVR.push(["encerrarProposta()", await gasDeChamada(
    rvr.connect(clube).encerrarProposta(0))]);

  // ───────────────── ERC-721 (RiverIngresso721) ─────────────────
  const NFT = await ethers.getContractFactory("RiverIngresso721");
  const nft = await NFT.deploy();
  await nft.waitForDeployment();
  comp["ERC-721"] = { deploy: await gasDeDeploy(nft) };
  comp["ERC-721"].mint = await gasDeChamada(nft.emitir(torcedor.address));
  comp["ERC-721"].transfer1 = await gasDeChamada(
    nft.connect(torcedor).transferFrom(torcedor.address, outro.address, 0));
  // "batch" de 10 (o ERC-721 nao tem batch nativo: mint em laco)
  comp["ERC-721"].batch10 = await gasDeChamada(nft.emitirLote(outro.address, 10));

  // ───────────────── ERC-1155 (RiverMulti1155) ─────────────────
  const MULTI = await ethers.getContractFactory("RiverMulti1155");
  const multi = await MULTI.deploy();
  await multi.waitForDeployment();
  comp["ERC-1155"] = { deploy: await gasDeDeploy(multi) };
  comp["ERC-1155"].mint = await gasDeChamada(multi.emitir(torcedor.address, 1, 1));
  comp["ERC-1155"].transfer1 = await gasDeChamada(
    multi.connect(torcedor).safeTransferFrom(torcedor.address, outro.address, 1, 1, "0x"));
  // batch nativo: 10 ids de uma vez
  const ids = Array.from({ length: 10 }, (_, i) => i + 100);
  const qts = Array.from({ length: 10 }, () => 1);
  comp["ERC-1155"].batch10 = await gasDeChamada(multi.emitirLote(outro.address, ids, qts));

  // ───────────────── Saida em Markdown ─────────────────
  const fmt = (n) => (n == null ? "n/d" : n.toLocaleString("pt-BR"));
  let md = "## Tabela 4.2 — Custo de gas por funcao (RiverToken)\n\n";
  md += "| Funcao | Gas |\n|---|---:|\n";
  for (const [nome, g] of linhasRVR) md += `| ${nome} | ${fmt(g)} |\n`;

  md += "\n## Tabela 4.5 — Comparacao de padroes (gas)\n\n";
  md += "| Operacao | ERC-20 ($RVR) | ERC-721 | ERC-1155 |\n|---|---:|---:|---:|\n";
  const row = (label, key) =>
    `| ${label} | ${fmt(comp["ERC-20 ($RVR)"][key])} | ${fmt(comp["ERC-721"][key])} | ${fmt(comp["ERC-1155"][key])} |\n`;
  md += row("Deploy", "deploy");
  md += row("Emissao (mint)", "mint");
  md += row("Transferencia (1)", "transfer1");
  md += `| Emissao em lote (10) | n/d | ${fmt(comp["ERC-721"].batch10)} | ${fmt(comp["ERC-1155"].batch10)} |\n`;

  console.log("\n" + md);
  fs.writeFileSync("docs/gas-report.md", md);
  console.log("Salvo em docs/gas-report.md");
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
