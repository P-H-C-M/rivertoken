// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./GovernancaBase.sol";
import "./RiverIdentidade721.sol";

/**
 * @title RiverToken20
 * @notice Implementação DIVIDIDA: token de governança fungível em ERC-20, que usa
 *         um contrato ERC-721 externo (RiverIdentidade721) para a identidade soulbound.
 *         RiverToken20 + RiverIdentidade721 = equivalente ao RiverDAO1155.
 */
contract RiverToken20 is ERC20, GovernancaBase {
    RiverIdentidade721 public identidade;

    constructor(address identidade721) ERC20("River Token", "RVR") {
        clube = msg.sender;
        identidade = RiverIdentidade721(identidade721);
        _mint(msg.sender, 6_000_000 ether);    // 60% clube
        _mint(address(this), 1_000_000 ether); // 10% fundo de staking
        fundoRecompensas = 1_000_000 ether;
        tetoVenda        = 3_000_000 ether;     // 30% venda pública
    }

    // ───────── virtuais da GovernancaBase ─────────
    function _saldoVotante(address c) internal view override returns (uint256) {
        return balanceOf(c) - tokensBloqueados[c] - stakes[c].quantidade;
    }
    function _saldoBruto(address c) internal view override returns (uint256) {
        return balanceOf(c);
    }
    function _supplyGov() internal view override returns (uint256) {
        return totalSupply();
    }
    function _emitirTokens(address para, uint256 qtd) internal override {
        _mint(para, qtd);
    }
    function _pagarRecompensa(address para, uint256 qtd) internal override {
        _transfer(address(this), para, qtd);
    }
    function _mintarIdentidade(address para) internal override {
        identidade.mintarPara(para); // credencial no contrato ERC-721 externo
    }

    // ───────── regras de transferência ─────────
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) {
            uint256 livre = balanceOf(from) - tokensBloqueados[from] - stakes[from].quantidade;
            require(value <= livre, "RVR: tokens bloqueados (voto/staking)");
        }
        super._update(from, to, value);
        if (to != address(0) && to != address(this)) {
            ultimaAquisicao[to] = block.timestamp;
        }
    }
}
