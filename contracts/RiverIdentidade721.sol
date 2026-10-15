// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RiverIdentidade721
 * @notice NFT de identidade SOULBOUND (não-transferível). Emitido pelo contrato de
 *         governança (RiverToken20) quando o usuário paga a taxa única de verificação.
 *         Junto com o RiverToken20, forma o equivalente ao RiverDAO1155.
 */
contract RiverIdentidade721 is ERC721, Ownable {
    address public dao;          // contrato de governança autorizado a emitir
    uint256 public proximoId = 1;

    constructor() ERC721("River Identidade", "RVRID") Ownable(msg.sender) {}

    /// @notice Liga o contrato de governança (uma única vez).
    function definirDAO(address novoDao) external onlyOwner {
        require(dao == address(0), "RVRID: DAO ja definido");
        dao = novoDao;
    }

    /// @notice Emite a credencial de identidade (só o DAO chama, na verificação).
    function mintarPara(address para) external returns (uint256 id) {
        require(msg.sender == dao, "RVRID: apenas o DAO");
        id = proximoId++;
        _safeMint(para, id);
    }

    function verificado(address conta) external view returns (bool) {
        return balanceOf(conta) > 0;
    }

    // Soulbound: permite apenas emissão (mint) e queima (burn), nunca transferência.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = super._update(to, tokenId, auth);
        if (from != address(0) && to != address(0)) revert("RVRID: identidade e soulbound");
    }
}
