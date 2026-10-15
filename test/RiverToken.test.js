const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

/**
 * Testes do River Token.
 *   - Funcionalidade: distribuicao, compra, staking nao-inflacionario.
 *   - ROBUSTEZ (Secao 4.4 do relatorio): prova que o contrato se DEFENDE de
 *     voto duplo, vote-and-run e flash-buy (via cooldown).
 *   Rode com: npx hardhat test
 */
describe("RiverToken", function () {
  async function deploy() {
    const [clube, ana, bruno] = await ethers.getSigners();
    const RVR = await ethers.getContractFactory("RiverToken");
    const rvr = await RVR.deploy();
    await rvr.waitForDeployment();
    return { rvr, clube, ana, bruno };
  }

  // compra padrao: 0.1 ETH -> 1000 RVR (preco 0.0001 ETH)
  async function comprar(rvr, quem, eth = "0.1") {
    await rvr.connect(quem).comprar({ value: ethers.parseEther(eth) });
  }

  describe("Distribuicao e supply", function () {
    it("mint 60% ao clube e 10% ao fundo de staking no deploy", async function () {
      const { rvr, clube } = await deploy();
      expect(await rvr.balanceOf(clube.address)).to.equal(ethers.parseEther("6000000"));
      expect(await rvr.balanceOf(await rvr.getAddress())).to.equal(ethers.parseEther("1000000"));
      expect(await rvr.fundoRecompensas()).to.equal(ethers.parseEther("1000000"));
      expect(await rvr.totalSupply()).to.equal(ethers.parseEther("7000000")); // 30% venda sob demanda
    });

    it("respeita o teto de supply e o estoque de venda", async function () {
      const { rvr } = await deploy();
      expect(await rvr.totalSupply()).to.be.lte(await rvr.MAX_SUPPLY());
    });
  });

  describe("Compra com ETH nativo", function () {
    it("emite a quantidade correta e contabiliza a venda", async function () {
      const { rvr, ana } = await deploy();
      await comprar(rvr, ana, "0.1");
      expect(await rvr.balanceOf(ana.address)).to.equal(ethers.parseEther("1000"));
      expect(await rvr.totalVendido()).to.equal(ethers.parseEther("1000"));
    });

    it("bloqueia compra quando a venda esta inativa", async function () {
      const { rvr, clube, ana } = await deploy();
      await rvr.connect(clube).setVendaAtiva(false);
      await expect(comprar(rvr, ana)).to.be.revertedWith("RVR: venda inativa");
    });
  });

  describe("Governanca", function () {
    it("registra voto por peso e trava os tokens (anti fraude)", async function () {
      const { rvr, clube, ana } = await deploy();
      await comprar(rvr, ana); // 1000 RVR
      await rvr.connect(clube).criarProposta("Musica de gol", 7 * 24 * 3600);
      await rvr.connect(ana).votar(0, true);
      expect(await rvr.tokensBloqueados(ana.address)).to.equal(ethers.parseEther("1000"));
    });

    it("impede votar duas vezes na mesma proposta", async function () {
      const { rvr, clube, ana } = await deploy();
      await comprar(rvr, ana);
      await rvr.connect(clube).criarProposta("P", 7 * 24 * 3600);
      await rvr.connect(ana).votar(0, true);
      await expect(rvr.connect(ana).votar(0, true)).to.be.revertedWith("RVR: ja votou");
    });

    it("[ROBUSTEZ] bloqueia vote-and-run: nao transfere tokens durante a votacao", async function () {
      const { rvr, clube, ana, bruno } = await deploy();
      await comprar(rvr, ana);
      await rvr.connect(clube).criarProposta("P", 7 * 24 * 3600);
      await rvr.connect(ana).votar(0, true);
      // tenta "correr" com os tokens logo apos votar -> deve falhar
      await expect(
        rvr.connect(ana).transfer(bruno.address, ethers.parseEther("1"))
      ).to.be.revertedWith("RVR: tokens bloqueados (voto/staking)");
      // apos o encerramento, os tokens sao liberados
      await time.increase(8 * 24 * 3600);
      await rvr.connect(clube).encerrarProposta(0);
      expect(await rvr.tokensBloqueados(ana.address)).to.equal(0);
      await expect(rvr.connect(ana).transfer(bruno.address, ethers.parseEther("1"))).to.not.be.reverted;
    });

    it("[ROBUSTEZ] cooldown bloqueia flash-buy: comprador recente nao vota", async function () {
      const { rvr, clube, ana } = await deploy();
      await rvr.connect(clube).setCooldownVoto(24 * 3600); // 1 dia de carencia
      await rvr.connect(clube).criarProposta("P", 7 * 24 * 3600);
      await comprar(rvr, ana); // compra AGORA (flash-buy)
      await expect(rvr.connect(ana).votar(0, true))
        .to.be.revertedWith("RVR: cooldown ativo (aguarde para votar)");
      // depois de cumprir a carencia, pode votar
      await time.increase(24 * 3600 + 1);
      await expect(rvr.connect(ana).votar(0, true)).to.not.be.reverted;
    });
  });

  describe("Staking nao-inflacionario", function () {
    it("paga recompensa do fundo pre-alocado sem aumentar o supply", async function () {
      const { rvr, ana } = await deploy();
      await comprar(rvr, ana, "1"); // 10.000 RVR
      const supplyAntes = await rvr.totalSupply();
      const fundoAntes = await rvr.fundoRecompensas();

      await rvr.connect(ana).stake(ethers.parseEther("10000"));
      await time.increase(365 * 24 * 3600); // 1 ano -> ~5%
      const saldoAntes = await rvr.balanceOf(ana.address);
      await rvr.connect(ana).unstake(ethers.parseEther("10000"));
      const saldoDepois = await rvr.balanceOf(ana.address);

      expect(saldoDepois).to.be.gt(saldoAntes);                 // recebeu recompensa
      expect(await rvr.totalSupply()).to.equal(supplyAntes);    // NAO inflacionario
      expect(await rvr.fundoRecompensas()).to.be.lt(fundoAntes);// saiu do fundo
    });

    it("[ROBUSTEZ] impede transferir tokens que estao em staking", async function () {
      const { rvr, ana, bruno } = await deploy();
      await comprar(rvr, ana, "1"); // 10.000 RVR
      await rvr.connect(ana).stake(ethers.parseEther("10000"));
      await expect(
        rvr.connect(ana).transfer(bruno.address, ethers.parseEther("1"))
      ).to.be.revertedWith("RVR: tokens bloqueados (voto/staking)");
    });
  });
});
