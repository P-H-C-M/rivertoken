const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const E = (n) => ethers.parseEther(String(n));
const TAXA = E("0.005");

describe("RiverDAO1155 (unificado)", function () {
  async function deploy() {
    const [clube, ana, bruno, carla] = await ethers.getSigners();
    const F = await ethers.getContractFactory("RiverDAO1155");
    const dao = await F.deploy();
    await dao.waitForDeployment();
    return { dao, clube, ana, bruno, carla };
  }
  const ID_RVR = 0n;
  async function comprar(dao, quem, eth) { await dao.connect(quem).comprar({ value: E(eth) }); }
  async function verificar(dao, quem) { await dao.connect(quem).verificarIdentidade({ value: TAXA }); }

  it("distribui 60% ao clube e 10% ao fundo no deploy", async function () {
    const { dao, clube } = await deploy();
    expect(await dao.balanceOf(clube.address, ID_RVR)).to.equal(E("6000000"));
    expect(await dao.balanceOf(await dao.getAddress(), ID_RVR)).to.equal(E("1000000"));
  });

  describe("Identidade anti-Sybil", function () {
    it("cobra a taxa, emite NFT soulbound e nao gera tokens de governanca", async function () {
      const { dao, ana } = await deploy();
      await verificar(dao, ana);
      expect(await dao.verificado(ana.address)).to.equal(true);
      const id = await dao.idIdentidadeDe(ana.address);
      expect(await dao.balanceOf(ana.address, id)).to.equal(1n);       // NFT de identidade
      expect(await dao.balanceOf(ana.address, ID_RVR)).to.equal(0n);   // nao gerou $RVR
    });
    it("rejeita taxa insuficiente e verificacao dupla", async function () {
      const { dao, ana } = await deploy();
      await expect(dao.connect(ana).verificarIdentidade({ value: E("0.001") }))
        .to.be.revertedWith("GOV: taxa insuficiente");
      await verificar(dao, ana);
      await expect(dao.connect(ana).verificarIdentidade({ value: TAXA }))
        .to.be.revertedWith("GOV: ja verificado");
    });
    it("[ROBUSTEZ] identidade e soulbound (nao transfere)", async function () {
      const { dao, ana, bruno } = await deploy();
      await verificar(dao, ana);
      const id = await dao.idIdentidadeDe(ana.address);
      await expect(
        dao.connect(ana).safeTransferFrom(ana.address, bruno.address, id, 1, "0x")
      ).to.be.revertedWith("RVR: identidade e soulbound");
    });
    it("exige identidade para votar", async function () {
      const { dao, clube, ana } = await deploy();
      await comprar(dao, ana, "0.1");
      await dao.connect(clube).criarProposta("P", 0, 0, ethers.ZeroAddress);
      await expect(dao.connect(ana).votar(0, true, E("100")))
        .to.be.revertedWith("GOV: identidade nao verificada");
    });
  });

  describe("Voto quadratico", function () {
    it("peso = raiz quadrada da quantidade comprometida", async function () {
      const { dao, clube, ana, bruno } = await deploy();
      await comprar(dao, ana, "0.1"); await verificar(dao, ana);   // 1000 RVR
      await comprar(dao, bruno, "0.4"); await verificar(dao, bruno); // 4000 RVR
      await dao.connect(clube).criarProposta("P", 0, 0, ethers.ZeroAddress);
      await dao.connect(ana).votar(0, true, E("100"));   // sqrt(100e18) = 1e10
      await dao.connect(bruno).votar(0, true, E("400"));  // sqrt(400e18) = 2e10
      const r = await dao.propostas(0);
      expect(r.votosSim).to.equal(10n ** 10n + 2n * 10n ** 10n); // 3e10
    });
  });

  describe("Propostas por tier e moderacao", function () {
    it("bloqueia proposta de quem esta abaixo de Ouro", async function () {
      const { dao, ana } = await deploy();
      await comprar(dao, ana, "0.1"); // 1000 RVR (Prata)
      await expect(dao.connect(ana).criarProposta("P", 0, 0, ethers.ZeroAddress))
        .to.be.revertedWith("GOV: precisa ser tier Ouro+");
    });
    it("Ouro pode propor, mas fica pendente ate o clube moderar", async function () {
      const { dao, clube, ana, bruno } = await deploy();
      await comprar(dao, ana, "0.5"); await verificar(dao, ana);   // 5000 RVR (Ouro)
      await comprar(dao, bruno, "0.1"); await verificar(dao, bruno);
      await dao.connect(ana).criarProposta("Proposta da torcida", 0, 0, ethers.ZeroAddress);
      // pendente: nao da para votar ainda
      await expect(dao.connect(bruno).votar(0, true, E("100")))
        .to.be.revertedWith("GOV: votacao indisponivel");
      await dao.connect(clube).moderarProposta(0, true); // clube aprova
      await expect(dao.connect(bruno).votar(0, true, E("100"))).to.not.be.reverted;
    });
    it("limite semanal: Ouro 1/semana, Platina 2/semana", async function () {
      const { dao, ana, bruno } = await deploy();
      await comprar(dao, ana, "0.5");  // Ouro (5000)
      await comprar(dao, bruno, "2");  // Platina (20000)
      await dao.connect(ana).criarProposta("A1", 0, 0, ethers.ZeroAddress);
      await expect(dao.connect(ana).criarProposta("A2", 0, 0, ethers.ZeroAddress))
        .to.be.revertedWith("GOV: limite semanal de propostas");
      await dao.connect(bruno).criarProposta("B1", 0, 0, ethers.ZeroAddress);
      await dao.connect(bruno).criarProposta("B2", 0, 0, ethers.ZeroAddress);
      await expect(dao.connect(bruno).criarProposta("B3", 0, 0, ethers.ZeroAddress))
        .to.be.revertedWith("GOV: limite semanal de propostas");
    });
  });

  describe("Emissao de novos tokens via votacao (pos-10M)", function () {
    it("minta apos aprovacao, respeitando teto e intervalo", async function () {
      const { dao, clube } = await deploy();
      await verificar(dao, clube);
      const supplyAntes = await dao["totalSupply(uint256)"](ID_RVR);
      // proposta de emissao de 100.000 (< 5% do supply)
      await dao.connect(clube).criarProposta("Emitir p/ marketing", 1, E("100000"), clube.address);
      await dao.connect(clube).votar(0, true, E("1000000"));
      await time.increase(7 * 24 * 3600 + 1);
      await dao.connect(clube).encerrarProposta(0);
      expect(await dao["totalSupply(uint256)"](ID_RVR)).to.equal(supplyAntes + E("100000"));
    });
    it("[ROBUSTEZ] rejeita emissao acima do teto de 5%", async function () {
      const { dao, clube } = await deploy();
      await verificar(dao, clube);
      await dao.connect(clube).criarProposta("Emissao gigante", 1, E("1000000"), clube.address); // >5%
      await dao.connect(clube).votar(0, true, E("1000000"));
      await time.increase(7 * 24 * 3600 + 1);
      await expect(dao.connect(clube).encerrarProposta(0))
        .to.be.revertedWith("GOV: acima do teto de emissao");
    });
  });
});

describe("RiverToken20 + RiverIdentidade721 (equivalente dividido)", function () {
  async function deploy() {
    const [clube, ana, bruno] = await ethers.getSigners();
    const ID = await (await ethers.getContractFactory("RiverIdentidade721")).deploy();
    await ID.waitForDeployment();
    const TK = await (await ethers.getContractFactory("RiverToken20")).deploy(await ID.getAddress());
    await TK.waitForDeployment();
    await ID.definirDAO(await TK.getAddress());
    return { ID, TK, clube, ana, bruno };
  }

  it("verificacao no ERC-20 emite a credencial no ERC-721 soulbound", async function () {
    const { ID, TK, ana, bruno } = await deploy();
    await TK.connect(ana).verificarIdentidade({ value: TAXA });
    expect(await ID.balanceOf(ana.address)).to.equal(1n);
    expect(await TK.verificado(ana.address)).to.equal(true);
    await expect(
      ID.connect(ana).transferFrom(ana.address, bruno.address, 1)
    ).to.be.revertedWith("RVRID: identidade e soulbound");
  });

  it("voto quadratico funciona igual ao 1155", async function () {
    const { TK, clube, ana } = await deploy();
    await TK.connect(ana).comprar({ value: E("0.1") });
    await TK.connect(ana).verificarIdentidade({ value: TAXA });
    await TK.connect(clube).criarProposta("P", 0, 0, ethers.ZeroAddress);
    await TK.connect(ana).votar(0, true, E("100"));
    const r = await TK.propostas(0);
    expect(r.votosSim).to.equal(10n ** 10n); // sqrt(100e18)
  });
});
