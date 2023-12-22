// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./IERC721Receiver.sol";

contract Lock is IERC721Receiver {
    uint256 public lockTime;
    address public nftAddress;

    event LockNFT(uint256 tokenId,address user);
    event UnlockNFT(uint256 tokenId,address user);

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory 
    ) external virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    modifier onlyCreator() {
        _checkCreator();
        _;
    }

    function _checkCreator() internal view virtual {}

    function lockNFT(address _nftAddress, uint256 tokenId) external onlyCreator {

        require(IERC721(_nftAddress).getApproved(tokenId) == address(this), "LOCK: Caller is not approved");

        IERC721(_nftAddress).safeTransferFrom(msg.sender, address(this), tokenId);

        if (lockTime==0) {
            lockTime = block.timestamp + 365*24*3600;
        }

        nftAddress = _nftAddress;

        emit LockNFT(tokenId, msg.sender);
    }

    function unlockNFT(uint256 tokenId) external onlyCreator {
        require(nftAddress != address(0), "LOCK: unlock nothing");
        require(lockTime > 0 && lockTime < block.timestamp, "LOCK: lock time");

        IERC721(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId);
        emit UnlockNFT(tokenId, msg.sender);
    }
}
