# River Token ($RVR) — DAO experimental

Fan token do River Atlético Clube com **governança on-chain (DAO)**: voto **quadrático**,
verificação de **identidade anti-Sybil** (NFT soulbound por taxa única), direito de **propor
por tier** (Ouro 1/semana, Platina 2/semana), **moderação** do clube para propostas da torcida,
**staking não-inflacionário**, **compra com ETH nativo**, defesa contra **vote-and-run** (trava +
carência) e **emissão de novos tokens por votação** após os 10M iniciais.

Projeto da disciplina *Tópicos em Computação* (UFPI). Contém o código e os experimentos da
seção de **Avaliação** do relatório.

## Estrutura do repositório

```
contracts/   contratos Solidity
test/        testes automatizados (Hardhat)
scripts/     deploy e medição de gas
frontend/    dApp (index.html + MetaMask) — veja frontend/README.md
docs/        relatório (.docx) e relatórios de gas
```

## Contratos

| Arquivo | Papel |
|---|---|
| `contracts/GovernancaBase.sol` | Lógica de governança compartilhada (abstrata). |
| `contracts/RiverDAO1155.sol` | **DAO completa unificada em ERC-1155** (token + identidade). |
| `contracts/RiverToken20.sol` | ERC-20 de governança (par do 721). |
| `contracts/RiverIdentidade721.sol` | ERC-721 de identidade soulbound (par do 20). |
| `contracts/RiverToken.sol` | Versão ERC-20 anterior (mantida para referência/comparação). |
| `contracts/RiverIngresso721.sol`, `RiverMulti1155.sol` | Contratos mínimos p/ comparar gas. |

> **RiverToken20 + RiverIdentidade721** juntos são o equivalente "dividido" do **RiverDAO1155**.

## Instalação

```bash
npm install
```

## Rodar tudo localmente (sem custo, sem carteira)

```bash
npm run compile
npm test                                   # todos os testes (funcionalidade + robustez)
npx hardhat run scripts/medir-gas.js       # gas dos contratos mínimos -> docs/gas-report.md
npx hardhat run scripts/medir-gas-dao.js   # gas 1155 unificado vs 20+721 -> docs/gas-report-dao.md
```

O gas na rede local do Hardhat é **idêntico** ao da Sepolia (depende do opcode, não da rede).

## Deploy na testnet Sepolia

1. Crie uma carteira de teste (ex.: MetaMask) e pegue **Sepolia ETH grátis** num faucet
   (ex.: sepoliafaucet.com, faucet.quicknode.com/ethereum/sepolia).
2. Crie conta gratuita na **Alchemy** ou **Infura** e copie a URL RPC da Sepolia.
3. Copie `.env.example` para `.env` e preencha `SEPOLIA_RPC_URL` e `PRIVATE_KEY`.
4. Faça o deploy (anote os endereços impressos):

```bash
npm run deploy:sepolia
```

> ⚠️ Nunca suba o `.env` (com a chave privada) para o GitHub ou Sigaa.

## Como testar na Sepolia (passo a passo)

Use o console do Hardhat conectado à Sepolia, ou o Remix/Etherscan com os endereços do deploy.
Fluxo sugerido no **RiverDAO1155** (ID do token de governança = 0):

```bash
npx hardhat console --network sepolia
```
```js
const dao = await ethers.getContractAt("RiverDAO1155", "ENDERECO_DO_DEPLOY");
const [conta] = await ethers.getSigners();

// 1) Comprar $RVR com ETH nativo (0.1 ETH -> 1000 RVR)
await dao.comprar({ value: ethers.parseEther("0.1") });

// 2) Verificar identidade (taxa única -> NFT soulbound; exigido para votar)
await dao.verificarIdentidade({ value: ethers.parseEther("0.005") });

// 3) Clube cria uma proposta (o deployer é o clube)
await dao.criarProposta("Novo uniforme 2026", 0, 0, ethers.ZeroAddress);

// 4) Votar comprometendo 100 RVR (peso quadrático = raiz de 100e18)
await dao.votar(0, true, ethers.parseEther("100"));

// 5) Após o prazo (7 dias), encerrar e ver o resultado
await dao.encerrarProposta(0);
await dao.resultadoProposta(0);
```

Para testar a **emissão pós-10M**: `criarProposta("Emitir", 1, ethers.parseEther("100000"), enderecoDestino)`,
votar, aguardar o prazo e `encerrarProposta` — os tokens são mintados se aprovado (teto de 5% e
intervalo de 90 dias). Para a **moderação**, uma carteira tier Ouro+ chama `criarProposta` e o
clube decide com `moderarProposta(id, true/false)`.

Cada tentativa de ataque (voto duplo, vote-and-run, flash-buy sem cumprir o cooldown, transferir
identidade ou tokens travados) é **revertida** pelo contrato — os testes automatizados comprovam.

## Parâmetros principais

- Supply inicial: 10.000.000 $RVR (60% clube, 10% fundo de staking, 30% venda). Após isso, só via votação.
- Preço inicial: 0,0001 ETH/$RVR. Taxa de identidade: 0,005 ETH (única, não gera tokens).
- Staking: 5% a.a. (teto 50%), pago do fundo pré-alocado. Cooldown de voto: configurável (`setCooldownVoto`).
- Emissão: até 5% do supply por rodada, no máximo a cada 90 dias, sempre por votação aprovada.

## Front-end

```bash
cd frontend && python3 -m http.server 8000   # http://localhost:8000
```
