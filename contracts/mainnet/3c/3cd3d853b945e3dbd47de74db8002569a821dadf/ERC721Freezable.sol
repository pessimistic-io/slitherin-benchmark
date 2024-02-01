// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";

abstract contract ERC721Freezable is ERC721 {
    mapping(address => bool) public frozenAccount;
    mapping(uint256 => bool) public frozenToken;
    event FrozenAccount(address target, bool frozen);
    event FrozenToken(uint256 target, bool frozen);

    function _freezeAccount(address target, bool freeze) internal virtual {
        frozenAccount[target] = freeze;
        emit FrozenAccount(target, freeze);
    }

    function _freezeToken(uint256 target, bool freeze) internal virtual {
        frozenToken[target] = freeze;
        emit FrozenToken(target, freeze);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        require(!frozenAccount[from], "frozen account");
        require(!frozenToken[tokenId], "frozen token");
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function approve(address to, uint256 tokenId) public virtual override {
        require(!frozenAccount[msg.sender], "frozen account");
        require(!frozenToken[tokenId], "frozen token");
        super.approve(to, tokenId);
    }
}

