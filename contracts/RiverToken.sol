// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RiverToken ($RVR)
 * @notice Fan token ERC-20 do River Atlético Clube com governança on-chain (DAO),
 *         staking não-inflacionário, compra com ETH nativo e mecanismos de defesa
 *         contra "vote-and-run" (trava de tokens na votação + carência/cooldown).
 *
 * Distribuição do supply (total 10.000.000 $RVR):
 *   - 60% clube          (mintado ao owner no deploy)
 *   - 10% fundo staking   (mintado ao contrato no deploy — NÃO inflacionário)
 *   - 30% venda pública   (mintado sob demanda em comprar(), até o teto)
 */
contract RiverToken is ERC20, Ownable {
    // ───────────────────────── 1. Constantes e estado ─────────────────────────
    uint256 public constant MAX_SUPPLY   = 10_000_000 ether; // 10M * 1e18
    uint256 public constant PARTE_CLUBE   = 60;
    uint256 public constant PARTE_STAKING = 10;
    uint256 public constant PARTE_VENDA   = 30;

    // Venda pública
    uint256 public precoTokenWei = 0.0001 ether; // preço de 1 $RVR em wei
    bool    public vendaAtiva    = true;
    uint256 public totalVendido;

    // Tiers de fidelidade (em tokens)
    uint256 public constant TIER_BRONZE  = 100 ether;
    uint256 public constant TIER_PRATA   = 1_000 ether;
    uint256 public constant TIER_OURO    = 5_000 ether;
    uint256 public constant TIER_PLATINA = 20_000 ether;

    // Governança
    struct Proposta {
        string  descricao;
        uint256 prazoFim;
        uint256 votosSim;
        uint256 votosNao;
        bool    encerrada;
    }
    Proposta[] public propostas;
    mapping(uint256 => mapping(address => bool))    public jaVotou;
    mapping(uint256 => mapping(address => uint256)) public pesoUsado;
    mapping(uint256 => address[])                   private _votantes;
    mapping(address => uint256)                     public tokensBloqueados;

    // Carência (cooldown): tempo mínimo de posse antes de poder votar
    uint256 public cooldownVoto;                        // em segundos (0 = desligado)
    mapping(address => uint256) public ultimaAquisicao; // timestamp da última entrada de tokens

    // Staking não-inflacionário
    struct StakeInfo { uint256 quantidade; uint256 desde; }
    mapping(address => StakeInfo) public stakes;
    uint256 public fundoRecompensas;        // reserva de 10% para pagar recompensas
    uint256 public rewardRateBps = 500;     // 5% a.a. (500 bps); teto de 50%

    // ───────────────────────── Eventos ─────────────────────────
    event Compra(address indexed comprador, uint256 quantidade, uint256 pagoWei);
    event PropostaCriada(uint256 indexed id, string descricao, uint256 prazoFim);
    event Voto(uint256 indexed id, address indexed eleitor, bool apoia, uint256 peso);
    event PropostaEncerrada(uint256 indexed id, uint256 votosSim, uint256 votosNao, bool aprovada);
    event Stake(address indexed usuario, uint256 quantidade);
    event Unstake(address indexed usuario, uint256 principal, uint256 recompensa);

    // ───────────────────────── 2. Construtor ─────────────────────────
    constructor() ERC20("River Token", "RVR") Ownable(msg.sender) {
        uint256 parteClube   = (MAX_SUPPLY * PARTE_CLUBE)   / 100; // 6.000.000
        uint256 parteStaking = (MAX_SUPPLY * PARTE_STAKING) / 100; // 1.000.000
        _mint(msg.sender, parteClube);        // clube
        _mint(address(this), parteStaking);   // fundo de staking (reservado)
        fundoRecompensas = parteStaking;
        // Os 30% da venda pública são mintados sob demanda em comprar().
    }

    // ───────── 3. Override _update: trava anti-fraude de transferência ─────────
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) {
            uint256 disponivel = balanceOf(from) - tokensBloqueados[from] - stakes[from].quantidade;
            require(value <= disponivel, "RVR: tokens bloqueados (voto/staking)");
        }
        super._update(from, to, value);
        // Recebimento de tokens reinicia o relogio de carencia (anti flash-buy)
        if (to != address(0) && to != address(this)) {
            ultimaAquisicao[to] = block.timestamp;
        }
    }

    // ───────────────────────── 4. Compra com ETH nativo ─────────────────────────
    function comprar() external payable {
        require(vendaAtiva, "RVR: venda inativa");
        require(msg.value > 0, "RVR: envie ETH");
        uint256 qtd = (msg.value * 1 ether) / precoTokenWei;
        require(qtd > 0, "RVR: valor insuficiente");
        require(totalVendido + qtd <= (MAX_SUPPLY * PARTE_VENDA) / 100, "RVR: estoque de venda esgotado");
        require(totalSupply() + qtd <= MAX_SUPPLY, "RVR: supply maximo atingido");
        totalVendido += qtd;
        _mint(msg.sender, qtd);
        emit Compra(msg.sender, qtd, msg.value);
    }

    function custoDeCompra(uint256 quantidade) external view returns (uint256) {
        return (quantidade * precoTokenWei) / 1 ether;
    }

    function setPreco(uint256 novoPrecoWei) external onlyOwner {
        require(novoPrecoWei > 0, "RVR: preco invalido");
        precoTokenWei = novoPrecoWei;
    }

    function setVendaAtiva(bool ativa) external onlyOwner {
        vendaAtiva = ativa;
    }

    function sacarETH() external onlyOwner {
        uint256 saldo = address(this).balance;
        require(saldo > 0, "RVR: sem ETH");
        (bool ok, ) = payable(owner()).call{value: saldo}("");
        require(ok, "RVR: falha no saque");
    }

    // ───────────────────────── 5. Tiers de fidelidade ─────────────────────────
    function tierDe(address conta) external view returns (string memory) {
        uint256 saldo = balanceOf(conta);
        if (saldo >= TIER_PLATINA) return "Platina";
        if (saldo >= TIER_OURO)    return "Ouro";
        if (saldo >= TIER_PRATA)   return "Prata";
        if (saldo >= TIER_BRONZE)  return "Bronze";
        return "Nenhum";
    }

    // ───────────────────────── 6. Governança (criar / votar) ─────────────────────────
    function criarProposta(string calldata descricao, uint256 duracaoSegundos) external onlyOwner returns (uint256 id) {
        require(duracaoSegundos > 0, "RVR: duracao invalida");
        id = propostas.length;
        propostas.push(Proposta({
            descricao: descricao,
            prazoFim: block.timestamp + duracaoSegundos,
            votosSim: 0,
            votosNao: 0,
            encerrada: false
        }));
        emit PropostaCriada(id, descricao, block.timestamp + duracaoSegundos);
    }

    function votar(uint256 id, bool apoia) external {
        require(id < propostas.length, "RVR: proposta inexistente");
        Proposta storage p = propostas[id];
        require(!p.encerrada && block.timestamp < p.prazoFim, "RVR: votacao encerrada");
        require(!jaVotou[id][msg.sender], "RVR: ja votou");

        // Carencia (cooldown): exige tempo minimo de posse antes de votar.
        require(
            block.timestamp >= ultimaAquisicao[msg.sender] + cooldownVoto,
            "RVR: cooldown ativo (aguarde para votar)"
        );

        // Peso = saldo livre (descontados tokens bloqueados e em staking).
        uint256 peso = balanceOf(msg.sender) - tokensBloqueados[msg.sender] - stakes[msg.sender].quantidade;
        require(peso > 0, "RVR: sem tokens livres");

        jaVotou[id][msg.sender] = true;
        pesoUsado[id][msg.sender] = peso;
        _votantes[id].push(msg.sender);
        tokensBloqueados[msg.sender] += peso; // trava os tokens ate o encerramento

        if (apoia) p.votosSim += peso; else p.votosNao += peso;
        emit Voto(id, msg.sender, apoia, peso);
    }

    // ───────────────────────── 7. Encerramento e resultado ─────────────────────────
    function encerrarProposta(uint256 id) external {
        require(id < propostas.length, "RVR: proposta inexistente");
        Proposta storage p = propostas[id];
        require(!p.encerrada, "RVR: ja encerrada");
        require(block.timestamp >= p.prazoFim, "RVR: prazo em aberto");
        p.encerrada = true;
        // Libera os tokens bloqueados de todos os votantes desta proposta.
        address[] storage lista = _votantes[id];
        for (uint256 i = 0; i < lista.length; i++) {
            address v = lista[i];
            tokensBloqueados[v] -= pesoUsado[id][v];
        }
        emit PropostaEncerrada(id, p.votosSim, p.votosNao, p.votosSim > p.votosNao);
    }

    function resultadoProposta(uint256 id) external view returns (uint256 sim, uint256 nao, bool aprovada) {
        Proposta storage p = propostas[id];
        return (p.votosSim, p.votosNao, p.votosSim > p.votosNao);
    }

    function totalPropostas() external view returns (uint256) {
        return propostas.length;
    }

    function setCooldownVoto(uint256 segundos) external onlyOwner {
        cooldownVoto = segundos;
    }

    // ───────────────────────── 8. Staking não-inflacionário ─────────────────────────
    function stake(uint256 quantidade) external {
        require(quantidade > 0, "RVR: quantidade invalida");
        uint256 livre = balanceOf(msg.sender) - tokensBloqueados[msg.sender] - stakes[msg.sender].quantidade;
        require(quantidade <= livre, "RVR: saldo livre insuficiente");
        // Coleta recompensa pendente antes de alterar o principal.
        _coletarRecompensa(msg.sender);
        stakes[msg.sender].quantidade += quantidade;
        stakes[msg.sender].desde = block.timestamp;
        emit Stake(msg.sender, quantidade);
    }

    function unstake(uint256 quantidade) external {
        StakeInfo storage s = stakes[msg.sender];
        require(quantidade > 0 && quantidade <= s.quantidade, "RVR: quantidade invalida");
        uint256 recompensa = _coletarRecompensa(msg.sender);
        s.quantidade -= quantidade;
        s.desde = block.timestamp;
        emit Unstake(msg.sender, quantidade, recompensa);
    }

    function recompensaPendente(address usuario) public view returns (uint256) {
        StakeInfo storage s = stakes[usuario];
        if (s.quantidade == 0) return 0;
        uint256 tempo = block.timestamp - s.desde;
        uint256 bruta = (s.quantidade * rewardRateBps * tempo) / (10_000 * 365 days);
        uint256 teto  = s.quantidade / 2; // teto de 50% do principal
        if (bruta > teto) bruta = teto;
        if (bruta > fundoRecompensas) bruta = fundoRecompensas; // limitado ao fundo
        return bruta;
    }

    function _coletarRecompensa(address usuario) internal returns (uint256 recompensa) {
        recompensa = recompensaPendente(usuario);
        stakes[usuario].desde = block.timestamp;
        if (recompensa > 0) {
            fundoRecompensas -= recompensa;
            _transfer(address(this), usuario, recompensa); // paga do fundo pré-alocado (não minta)
        }
    }

    function setRewardRate(uint256 novoBps) external onlyOwner {
        require(novoBps <= 5_000, "RVR: maximo 50% a.a."); // teto de 5000 bps
        rewardRateBps = novoBps;
    }

    // Evita ETH preso: apenas comprar() aceita valor.
    receive() external payable {
        revert("RVR: use comprar()");
    }
}
