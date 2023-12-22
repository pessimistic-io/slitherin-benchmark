// SPDX-License-Identifier: GPL-2.0-or-later
// TransferPosition.sol
// Transfer the position NFT to another user address. 
pragma solidity = 0.7.6;

import "./Ownable.sol";
import "./INonfungiblePositionManager.sol";

contract TransferPosition is Ownable {
    INonfungiblePositionManager public positionManager;

    event PositionTransferred(uint256 indexed tokenId, address indexed to);

    constructor(address _positionManager) {
        require(_positionManager != address(0), "Invalid address");
        positionManager = INonfungiblePositionManager(_positionManager);
    }

    function setPositionManager(address _positionManager) external onlyOwner {
        require(_positionManager != address(0), "Invalid address");
        positionManager = INonfungiblePositionManager(_positionManager);
    }

    function transferPosition(uint256 tokenId, address to) external {
        require(msg.sender == positionManager.ownerOf(tokenId), "Not the owner");
        positionManager.approve(address(positionManager), tokenId);
        positionManager.safeTransferFrom(msg.sender, to, tokenId);
        emit PositionTransferred(tokenId, to);
    }
}

