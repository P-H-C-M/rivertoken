// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RiverIngresso721
 * @notice Versão MÍNIMA em ERC-721 (não-fungível) usada apenas para a comparação
 *         experimental de custo de gas com o ERC-20 e o ERC-1155 (Seção 4.5).
 *         Cada ingresso é um token único e indivisível.
 */
contract RiverIngresso721 is ERC721, Ownable {
    uint256 public proximoId;

    constructor() ERC721("River Ingresso", "RVRI") Ownable(msg.sender) {}

    /// @notice Emite um ingresso único para `para`.
    function emitir(address para) external onlyOwner returns (uint256 id) {
        id = proximoId++;
        _safeMint(para, id);
    }

    /// @notice Emite `n` ingressos em laço (ERC-721 não tem batch nativo).
    function emitirLote(address para, uint256 n) external onlyOwner {
        for (uint256 i = 0; i < n; i++) {
            _safeMint(para, proximoId++);
        }
    }
}
