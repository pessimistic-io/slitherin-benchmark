// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ZKBridgeErc721.sol";

contract ZKBridgeSBT is ZKBridgeErc721 {
    constructor(
        string memory _name,
        string memory _symbol
    ) ZKBridgeErc721(_name, _symbol) {}

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
        require(from == address(0) || to == address(0), "SoulBound");
    }
}

