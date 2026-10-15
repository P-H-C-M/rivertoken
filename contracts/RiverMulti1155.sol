// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RiverMulti1155
 * @notice Versão MÍNIMA em ERC-1155 (fungível + não-fungível no mesmo contrato)
 *         usada para a comparação experimental de gas (Seção 4.5). Suporta
 *         emissão e transferência EM LOTE (batch), vantagem central do padrão.
 *
 *   id 0  -> ativo fungível (ex.: pontos de fidelidade)
 *   id >0 -> ativos "não-fungíveis" (ex.: coleções de ingressos)
 */
contract RiverMulti1155 is ERC1155, Ownable {
    constructor() ERC1155("https://river.example/api/item/{id}.json") Ownable(msg.sender) {}

    function emitir(address para, uint256 id, uint256 quantidade) external onlyOwner {
        _mint(para, id, quantidade, "");
    }

    function emitirLote(address para, uint256[] calldata ids, uint256[] calldata quantidades) external onlyOwner {
        _mintBatch(para, ids, quantidades, "");
    }
}
