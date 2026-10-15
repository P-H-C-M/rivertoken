// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title GovernancaBase
 * @notice Lógica de governança compartilhada entre o RiverDAO1155 (unificado) e o
 *         par RiverToken20 + RiverIdentidade721 (equivalente). Concentra:
 *           - voto QUADRÁTICO (peso = raiz quadrada da quantidade comprometida);
 *           - direito de propor por TIER (Ouro: 1/semana, Platina: 2/semana);
 *           - fila de MODERAÇÃO: propostas de não-membros passam pelo clube;
 *           - EMISSÃO de novos tokens após os 10M via votação (com teto e intervalo);
 *           - identidade anti-Sybil (taxa única -> NFT soulbound) exigida para votar;
 *           - carência (cooldown), staking não-inflacionário e compra com ETH.
 *
 * As operações específicas de cada padrão de token são deixadas como `virtual`.
 */
abstract contract GovernancaBase {
    using Math for uint256;

    // ───────── parâmetros ─────────
    address public clube;
    uint256 public duracaoVotacao   = 7 days;
    uint256 public taxaVerificacao  = 0.005 ether; // taxa única de identidade (não gera tokens)
    uint256 public cooldownVoto;                   // 0 = desligado
    uint256 public rewardRateBps    = 500;         // staking: 5% a.a. (teto 50%)
    uint256 public tetoEmissaoBps   = 500;         // emissão: no máx. 5% do supply por rodada
    uint256 public intervaloEmissao = 90 days;     // emissões no máximo a cada 90 dias
    uint256 public ultimaEmissao;
    uint256 public taxasAcumuladas;                // ETH das taxas de identidade

    // venda pública
    uint256 public precoTokenWei = 0.0001 ether;
    bool    public vendaAtiva    = true;
    uint256 public totalVendido;
    uint256 public tetoVenda;                      // definido no construtor concreto
    uint256 public fundoRecompensas;               // reserva de staking (definida no construtor)

    // tiers (em tokens)
    uint256 public constant TIER_BRONZE  = 100 ether;
    uint256 public constant TIER_PRATA   = 1_000 ether;
    uint256 public constant TIER_OURO    = 5_000 ether;
    uint256 public constant TIER_PLATINA = 20_000 ether;

    enum Tipo { COMUM, EMISSAO }
    enum Status { PENDENTE, ATIVA, REJEITADA, ENCERRADA }
    struct Proposta {
        address proponente;
        string  descricao;
        Tipo    tipo;
        Status  status;
        uint256 prazoFim;
        uint256 votosSim;
        uint256 votosNao;
        uint256 valorEmissao;
        address destino;
    }
    Proposta[] public propostas;
    mapping(uint256 => mapping(address => bool))    public jaVotou;
    mapping(uint256 => mapping(address => uint256)) public tokensNoVoto;
    mapping(uint256 => address[])                   internal _votantes;
    mapping(address => uint256)                     public tokensBloqueados;

    // identidade anti-Sybil
    mapping(address => bool) public verificado;

    // carência
    mapping(address => uint256) public ultimaAquisicao;

    // limite de propostas por janela de 7 dias
    mapping(address => uint256) public janelaInicio;
    mapping(address => uint256) public propostasNaJanela;

    // staking
    struct StakeInfo { uint256 quantidade; uint256 desde; }
    mapping(address => StakeInfo) public stakes;

    // ───────── eventos ─────────
    event Verificado(address indexed conta, uint256 taxa);
    event Compra(address indexed comprador, uint256 quantidade);
    event PropostaCriada(uint256 indexed id, address indexed proponente, Tipo tipo, Status status);
    event Moderada(uint256 indexed id, bool aprovada);
    event Voto(uint256 indexed id, address indexed eleitor, bool apoia, uint256 peso);
    event PropostaEncerrada(uint256 indexed id, bool aprovada);
    event Emissao(uint256 indexed id, address destino, uint256 quantidade);

    modifier apenasClube() { require(msg.sender == clube, "GOV: nao e o clube"); _; }

    // ───────── virtuais (dependem do padrão de token) ─────────
    function _saldoVotante(address c) internal view virtual returns (uint256); // saldo livre (- bloqueado - staking)
    function _saldoBruto(address c)   internal view virtual returns (uint256); // saldo total (p/ tier)
    function _supplyGov()             internal view virtual returns (uint256); // supply do token de governança
    function _emitirTokens(address para, uint256 qtd) internal virtual;        // minta token de governança
    function _pagarRecompensa(address para, uint256 qtd) internal virtual;     // transfere do fundo do contrato
    function _mintarIdentidade(address para) internal virtual;                 // minta o NFT soulbound de identidade

    // ───────── identidade ─────────
    function verificarIdentidade() external payable {
        require(!verificado[msg.sender], "GOV: ja verificado");
        require(msg.value >= taxaVerificacao, "GOV: taxa insuficiente");
        verificado[msg.sender] = true;
        taxasAcumuladas += msg.value;
        _mintarIdentidade(msg.sender); // credencial (NAO gera tokens de governanca)
        emit Verificado(msg.sender, msg.value);
    }

    // ───────── tiers ─────────
    function tierDe(address c) public view returns (string memory) {
        uint256 s = _saldoBruto(c);
        if (s >= TIER_PLATINA) return "Platina";
        if (s >= TIER_OURO)    return "Ouro";
        if (s >= TIER_PRATA)   return "Prata";
        if (s >= TIER_BRONZE)  return "Bronze";
        return "Nenhum";
    }

    // ───────── compra com ETH ─────────
    function comprar() external payable {
        require(vendaAtiva, "GOV: venda inativa");
        require(msg.value > 0, "GOV: envie ETH");
        uint256 qtd = (msg.value * 1 ether) / precoTokenWei;
        require(qtd > 0, "GOV: valor insuficiente");
        require(totalVendido + qtd <= tetoVenda, "GOV: estoque esgotado");
        totalVendido += qtd;
        _emitirTokens(msg.sender, qtd);
        emit Compra(msg.sender, qtd);
    }

    // ───────── propostas ─────────
    function criarProposta(string calldata descricao, Tipo tipo, uint256 valorEmissao, address destino)
        external returns (uint256 id)
    {
        bool club = (msg.sender == clube);
        if (!club) {
            require(_saldoBruto(msg.sender) >= TIER_OURO, "GOV: precisa ser tier Ouro+");
            uint256 limite = _saldoBruto(msg.sender) >= TIER_PLATINA ? 2 : 1;
            if (block.timestamp >= janelaInicio[msg.sender] + 7 days) {
                janelaInicio[msg.sender] = block.timestamp;
                propostasNaJanela[msg.sender] = 0;
            }
            require(propostasNaJanela[msg.sender] < limite, "GOV: limite semanal de propostas");
            propostasNaJanela[msg.sender] += 1;
        }
        id = propostas.length;
        propostas.push(Proposta({
            proponente:   msg.sender,
            descricao:    descricao,
            tipo:         tipo,
            status:       club ? Status.ATIVA : Status.PENDENTE, // clube: direto para votação
            prazoFim:     club ? block.timestamp + duracaoVotacao : 0,
            votosSim:     0,
            votosNao:     0,
            valorEmissao: tipo == Tipo.EMISSAO ? valorEmissao : 0,
            destino:      tipo == Tipo.EMISSAO ? destino : address(0)
        }));
        emit PropostaCriada(id, msg.sender, tipo, club ? Status.ATIVA : Status.PENDENTE);
    }

    /// @notice Clube modera propostas de não-membros antes de irem a voto.
    function moderarProposta(uint256 id, bool aprovar) external apenasClube {
        Proposta storage p = propostas[id];
        require(p.status == Status.PENDENTE, "GOV: nao esta pendente");
        if (aprovar) {
            p.status = Status.ATIVA;
            p.prazoFim = block.timestamp + duracaoVotacao;
        } else {
            p.status = Status.REJEITADA;
        }
        emit Moderada(id, aprovar);
    }

    // ───────── voto quadrático ─────────
    function votar(uint256 id, bool apoia, uint256 quantidade) external {
        Proposta storage p = propostas[id];
        require(p.status == Status.ATIVA && block.timestamp < p.prazoFim, "GOV: votacao indisponivel");
        require(verificado[msg.sender], "GOV: identidade nao verificada");
        require(block.timestamp >= ultimaAquisicao[msg.sender] + cooldownVoto, "GOV: cooldown ativo");
        require(!jaVotou[id][msg.sender], "GOV: ja votou");
        require(quantidade > 0 && quantidade <= _saldoVotante(msg.sender), "GOV: saldo livre insuficiente");

        jaVotou[id][msg.sender] = true;
        tokensNoVoto[id][msg.sender] = quantidade;
        _votantes[id].push(msg.sender);
        tokensBloqueados[msg.sender] += quantidade; // trava (anti vote-and-run)

        uint256 peso = Math.sqrt(quantidade); // PESO QUADRÁTICO
        if (apoia) p.votosSim += peso; else p.votosNao += peso;
        emit Voto(id, msg.sender, apoia, peso);
    }

    function encerrarProposta(uint256 id) external {
        Proposta storage p = propostas[id];
        require(p.status == Status.ATIVA, "GOV: nao esta ativa");
        require(block.timestamp >= p.prazoFim, "GOV: prazo em aberto");
        p.status = Status.ENCERRADA;

        address[] storage lista = _votantes[id];
        for (uint256 i = 0; i < lista.length; i++) {
            tokensBloqueados[lista[i]] -= tokensNoVoto[id][lista[i]]; // libera os tokens
        }

        bool aprovada = p.votosSim > p.votosNao;
        // Emissão de novos tokens (pós-10M), se aprovada, com teto e intervalo.
        if (p.tipo == Tipo.EMISSAO && aprovada) {
            require(block.timestamp >= ultimaEmissao + intervaloEmissao, "GOV: intervalo de emissao");
            require(p.valorEmissao <= (_supplyGov() * tetoEmissaoBps) / 10_000, "GOV: acima do teto de emissao");
            ultimaEmissao = block.timestamp;
            _emitirTokens(p.destino, p.valorEmissao);
            emit Emissao(id, p.destino, p.valorEmissao);
        }
        emit PropostaEncerrada(id, aprovada);
    }

    function resultadoProposta(uint256 id) external view returns (uint256 sim, uint256 nao, bool aprovada, Status status) {
        Proposta storage p = propostas[id];
        return (p.votosSim, p.votosNao, p.votosSim > p.votosNao, p.status);
    }
    function totalPropostas() external view returns (uint256) { return propostas.length; }

    // ───────── staking não-inflacionário ─────────
    function stake(uint256 quantidade) external {
        require(quantidade > 0 && quantidade <= _saldoVotante(msg.sender), "GOV: saldo livre insuficiente");
        _coletarRecompensa(msg.sender);
        stakes[msg.sender].quantidade += quantidade;
        stakes[msg.sender].desde = block.timestamp;
    }

    function unstake(uint256 quantidade) external {
        StakeInfo storage s = stakes[msg.sender];
        require(quantidade > 0 && quantidade <= s.quantidade, "GOV: quantidade invalida");
        _coletarRecompensa(msg.sender);
        s.quantidade -= quantidade;
        s.desde = block.timestamp;
    }

    function recompensaPendente(address usuario) public view returns (uint256) {
        StakeInfo storage s = stakes[usuario];
        if (s.quantidade == 0) return 0;
        uint256 tempo = block.timestamp - s.desde;
        uint256 bruta = (s.quantidade * rewardRateBps * tempo) / (10_000 * 365 days);
        uint256 teto = s.quantidade / 2;
        if (bruta > teto) bruta = teto;
        if (bruta > fundoRecompensas) bruta = fundoRecompensas;
        return bruta;
    }

    function _coletarRecompensa(address usuario) internal {
        uint256 r = recompensaPendente(usuario);
        stakes[usuario].desde = block.timestamp;
        if (r > 0) {
            fundoRecompensas -= r;
            _pagarRecompensa(usuario, r); // paga do fundo pré-alocado (não minta)
        }
    }

    // ───────── administração ─────────
    function setPreco(uint256 wei_) external apenasClube { require(wei_ > 0, "GOV: preco"); precoTokenWei = wei_; }
    function setVendaAtiva(bool a) external apenasClube { vendaAtiva = a; }
    function setCooldownVoto(uint256 s) external apenasClube { cooldownVoto = s; }
    function setTaxaVerificacao(uint256 v) external apenasClube { taxaVerificacao = v; }

    function sacarETH() external apenasClube {
        uint256 saldo = address(this).balance;
        require(saldo > 0, "GOV: sem ETH");
        (bool ok, ) = payable(clube).call{value: saldo}("");
        require(ok, "GOV: falha no saque");
    }

    // impede ETH preso
    receive() external payable { revert("GOV: use comprar()/verificarIdentidade()"); }
}
