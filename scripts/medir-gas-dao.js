const hre = require("hardhat");
const fs = require("fs");
const { ethers } = hre;
const E = (n) => ethers.parseEther(String(n));
const TAXA = E("0.005");

async function gasTx(p) { const r = await (await p).wait(); return Number(r.gasUsed); }
async function gasDeploy(c) { return Number(await (await c.deploymentTransaction().wait()).gasUsed); }

async function main() {
  const [clube, ana] = await ethers.getSigners();
  const uni = {}, spl = {};

  // ───────── ERC-1155 unificado ─────────
  const DAO = await (await ethers.getContractFactory("RiverDAO1155")).deploy();
  await DAO.waitForDeployment();
  uni.deploy = await gasDeploy(DAO);
  uni.verificar = await gasTx(DAO.connect(ana).verificarIdentidade({ value: TAXA }));
  uni.comprar = await gasTx(DAO.connect(ana).comprar({ value: E("0.1") }));
  uni.criarProposta = await gasTx(DAO.connect(clube).criarProposta("P", 0, 0, ethers.ZeroAddress));
  uni.votar = await gasTx(DAO.connect(ana).votar(0, true, E("100")));
  await hre.network.provider.send("evm_increaseTime", [7 * 24 * 3600 + 1]);
  await hre.network.provider.send("evm_mine", []);
  uni.encerrar = await gasTx(DAO.connect(clube).encerrarProposta(0));

  // ───────── ERC-20 + ERC-721 (dividido) ─────────
  const ID = await (await ethers.getContractFactory("RiverIdentidade721")).deploy();
  await ID.waitForDeployment();
  const TK = await (await ethers.getContractFactory("RiverToken20")).deploy(await ID.getAddress());
  await TK.waitForDeployment();
  await ID.definirDAO(await TK.getAddress());
  spl.deploy = (await gasDeploy(ID)) + (await gasDeploy(TK)); // soma dos dois contratos
  spl.verificar = await gasTx(TK.connect(ana).verificarIdentidade({ value: TAXA })); // chama o 721 externo
  spl.comprar = await gasTx(TK.connect(ana).comprar({ value: E("0.1") }));
  spl.criarProposta = await gasTx(TK.connect(clube).criarProposta("P", 0, 0, ethers.ZeroAddress));
  spl.votar = await gasTx(TK.connect(ana).votar(0, true, E("100")));
  await hre.network.provider.send("evm_increaseTime", [7 * 24 * 3600 + 1]);
  await hre.network.provider.send("evm_mine", []);
  spl.encerrar = await gasTx(TK.connect(clube).encerrarProposta(0));

  const fmt = (n) => n.toLocaleString("pt-BR");
  const linha = (rot, k) => `| ${rot} | ${fmt(uni[k])} | ${fmt(spl[k])} |\n`;
  let md = "## Tabela 7 — DAO completa: ERC-1155 unificado vs ERC-20 + ERC-721 (gas)\n\n";
  md += "| Operação | ERC-1155 unificado | ERC-20 + ERC-721 |\n|---|---:|---:|\n";
  md += linha("Deploy (total)", "deploy");
  md += linha("verificarIdentidade()", "verificar");
  md += linha("comprar()", "comprar");
  md += linha("criarProposta()", "criarProposta");
  md += linha("votar() [quadrático]", "votar");
  md += linha("encerrarProposta()", "encerrar");

  console.log("\n" + md);
  fs.writeFileSync("docs/gas-report-dao.md", md);
  console.log("Salvo em docs/gas-report-dao.md");
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
