// SPDX-License-Identifier: UNLICENSED
// ALL RIGHTS RESERVED
// UNCX by SDDTech reserves all rights on this code. You may not copy these contracts.

pragma solidity 0.8.19;

import "./IERC721Receiver.sol";
import "./ReentrancyGuard.sol";

import "./IMigrateV3NFT.sol";
import "./INonfungiblePositionManager.sol";
import "./IUNCX_ProofOfReservesUniV3.sol";
import "./IUNCX_ProofOfReservesV2_UniV3.sol";

contract MigrateV3NFT is IMigrateV3NFT, IERC721Receiver, ReentrancyGuard {
    IUNCX_ProofOfReservesUniV3 public OLD_ProofOfReservesUniV3;
    IUNCX_ProofOfReservesV2_UniV3 public NEW_ProofOfReservesUniV3;

    constructor(IUNCX_ProofOfReservesUniV3 _Old_ProofOfReservesUniV3, IUNCX_ProofOfReservesV2_UniV3 _New_ProofOfReservesUniV3) {
        OLD_ProofOfReservesUniV3 = _Old_ProofOfReservesUniV3;
        NEW_ProofOfReservesUniV3 = _New_ProofOfReservesUniV3;
    }

    function migrate (uint256 _lockId, INonfungiblePositionManager _nftPositionManager, uint256 _tokenId) external override nonReentrant returns (bool) {
        require(msg.sender == address(OLD_ProofOfReservesUniV3), "SENDER NOT UNCX LOCKER");
        _nftPositionManager.safeTransferFrom(msg.sender, address(this), _tokenId);
        _nftPositionManager.approve(address(NEW_ProofOfReservesUniV3), _tokenId);
        
        IUNCX_ProofOfReservesUniV3.Lock memory v1lock = OLD_ProofOfReservesUniV3.getLock(_lockId);
        IUNCX_ProofOfReservesV2_UniV3.LockParams memory v2LockParams;

        v2LockParams.nftPositionManager = v1lock.nftPositionManager;
        v2LockParams.nft_id = v1lock.nft_id;
        v2LockParams.dustRecipient = v1lock.collectAddress;
        v2LockParams.owner = v1lock.owner;
        v2LockParams.additionalCollector = v1lock.additionalCollector;
        v2LockParams.collectAddress = v1lock.collectAddress;
        v2LockParams.unlockDate = v1lock.unlockDate;
        v2LockParams.countryCode = v1lock.countryCode;
        v2LockParams.r = new bytes[](1);
        v2LockParams.r[0] = abi.encode(v1lock.ucf);

        if (v2LockParams.unlockDate <= block.timestamp) {
            v2LockParams.unlockDate = block.timestamp + 1;
        }

        NEW_ProofOfReservesUniV3.lock(v2LockParams);

        return true;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
