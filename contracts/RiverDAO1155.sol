// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "./GovernancaBase.sol";

/**
 * @title RiverDAO1155
 * @notice Implementação UNIFICADA em ERC-1155: um único contrato reúne o token de
 *         governança fungível (id 0) e os NFTs de identidade soulbound (ids >= 1),
 *         além de toda a lógica de GovernancaBase (voto quadrático, tiers, moderação,
 *         emissão, staking, compra e cooldown).
 */
contract RiverDAO1155 is ERC1155Supply, GovernancaBase {
    uint256 public constant ID_RVR = 0;      // token de governança (fungível)
    uint256 private _contadorIdentidade;     // ids de identidade começam em 1
    mapping(address => uint256) public idIdentidadeDe;

    constructor() ERC1155("https://river.example/api/item/{id}.json") {
        clube = msg.sender;
        _mint(msg.sender, ID_RVR, 6_000_000 ether, "");   // 60% clube
        _mint(address(this), ID_RVR, 1_000_000 ether, ""); // 10% fundo de staking
        fundoRecompensas = 1_000_000 ether;
        tetoVenda        = 3_000_000 ether;                // 30% venda pública
    }

    // ───────── virtuais da GovernancaBase ─────────
    function _saldoVotante(address c) internal view override returns (uint256) {
        return balanceOf(c, ID_RVR) - tokensBloqueados[c] - stakes[c].quantidade;
    }
    function _saldoBruto(address c) internal view override returns (uint256) {
        return balanceOf(c, ID_RVR);
    }
    function _supplyGov() internal view override returns (uint256) {
        return totalSupply(ID_RVR);
    }
    function _emitirTokens(address para, uint256 qtd) internal override {
        _mint(para, ID_RVR, qtd, "");
    }
    function _pagarRecompensa(address para, uint256 qtd) internal override {
        _safeTransferFrom(address(this), para, ID_RVR, qtd, "");
    }
    function _mintarIdentidade(address para) internal override {
        uint256 id = ++_contadorIdentidade;   // NFT único e soulbound
        idIdentidadeDe[para] = id;
        _mint(para, id, 1, "");
    }

    // ───────── regras de transferência ─────────
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal override
    {
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == ID_RVR) {
                if (from != address(0)) {
                    uint256 livre = balanceOf(from, ID_RVR) - tokensBloqueados[from] - stakes[from].quantidade;
                    require(values[i] <= livre, "RVR: tokens bloqueados (voto/staking)");
                }
            } else {
                // Identidade é soulbound: não pode ser transferida entre carteiras.
                require(from == address(0) || to == address(0), "RVR: identidade e soulbound");
            }
        }
        super._update(from, to, ids, values);
        // carência: recebimento de token de governança reinicia o relogio
        if (to != address(0) && to != address(this)) {
            for (uint256 i = 0; i < ids.length; i++) {
                if (ids[i] == ID_RVR) { ultimaAquisicao[to] = block.timestamp; break; }
            }
        }
    }
}
