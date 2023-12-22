// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

// Storage imports
import { LibStorage, BattleflyGameStorage, PaymentType } from "./LibStorage.sol";
import { Errors } from "./Errors.sol";

//interfaces
import { IERC20 } from "./IERC20.sol";
import { IERC1155 } from "./IERC1155.sol";
import { IUniswapV2Router02 } from "./IUniswapV2Router02.sol";
import { IUniswapV2Pair } from "./IUniswapV2Pair.sol";
import { EnumerableSet } from "./EnumerableSet.sol";
import "./IBattlefly.sol";
import "./ISoulboundBattlefly.sol";
import "./draft-EIP712.sol";

library LibStakeUtils {
    using EnumerableSet for EnumerableSet.UintSet;

    event BulkStakeBattlefly(uint256[] tokenIds, uint256[] tokenTypes, address indexed user, uint256 totalMagicAmount);
    event BulkUnstakeBattlefly(
        uint256[] tokenIds,
        uint256[] tokenTypes,
        address indexed user,
        uint256 totalMagicAmount
    );

    function gs() internal pure returns (BattleflyGameStorage storage) {
        return LibStorage.gameStorage();
    }

    function bulkStakeBattlefly(uint256[] memory tokenIds, uint256[] memory tokenTypes) internal {
        if (tokenIds.length != tokenTypes.length) revert Errors.InvalidArrayLength();
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 tokenType = tokenTypes[i];
            gs().battleflyOwner[tokenId][tokenType] = msg.sender;
            gs().battlefliesOfOwner[msg.sender][tokenType].add(tokenId);
            if (tokenType == 0) {
                IBattlefly(gs().battlefly).safeTransferFrom(msg.sender, address(this), tokenId);
            } else if (tokenType == 1) {
                ISoulboundBattlefly(gs().soulbound).safeTransferFrom(msg.sender, address(this), tokenId);
            } else {
                revert Errors.InvalidTokenType(tokenId, tokenType);
            }
        }
        emit BulkStakeBattlefly(tokenIds, tokenTypes, msg.sender, 0);
    }

    function stakeSoulbound(address owner, uint256 tokenId) internal {
        gs().battleflyOwner[tokenId][1] = owner;
        gs().battlefliesOfOwner[owner][1].add(tokenId);
        ISoulboundBattlefly(gs().soulbound).safeTransferFrom(msg.sender, address(this), tokenId, "");
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory tokenTypes = new uint256[](1);
        tokenIds[0] = tokenId;
        tokenTypes[0] = 1;
        emit BulkStakeBattlefly(tokenIds, tokenTypes, owner, 0);
    }

    function bulkUnstakeBattlefly(
        uint256[] memory tokenIds,
        uint256[] memory tokenTypes,
        uint256[] memory battleflyStages,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        if (tokenIds.length != tokenTypes.length) revert Errors.InvalidArrayLength();
        bytes32 payloadHash = keccak256(abi.encodePacked(msg.sender, tokenIds, tokenTypes, battleflyStages));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", payloadHash));
        (address signer, ECDSA.RecoverError result) = ECDSA.tryRecover(messageHash, v, r, s);
        if (!(result == ECDSA.RecoverError.NoError && gs().signer[signer])) revert Errors.IncorrectSigner(signer);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 tokenType = tokenTypes[i];
            if (gs().battleflyOwner[tokenId][tokenType] != msg.sender)
                revert Errors.NotOwnerOfBattlefly(msg.sender, tokenId, tokenType);
            gs().battleflyOwner[tokenId][tokenType] = address(0);
            gs().battlefliesOfOwner[msg.sender][tokenType].remove(tokenId);
            if (tokenType == 0) {
                IBattlefly(gs().battlefly).safeTransferFrom(address(this), msg.sender, tokenId, "");
            } else if (tokenType == 1) {
                ISoulboundBattlefly(gs().soulbound).safeTransferFrom(address(this), msg.sender, tokenId, "");
            } else {
                revert Errors.InvalidTokenType(tokenId, tokenType);
            }
        }
        emit BulkUnstakeBattlefly(tokenIds, tokenTypes, msg.sender, 0);
    }

    function stakingBattlefliesOfOwner(address owner, uint256 tokenType) internal view returns (uint256[] memory) {
        if (owner == address(0)) revert Errors.InvalidAddress();
        return gs().battlefliesOfOwner[owner][tokenType].toArray();
    }

    function balanceOf(address owner, uint256 tokenType) internal view returns (uint256) {
        if (owner == address(0)) revert Errors.InvalidAddress();
        return gs().battlefliesOfOwner[owner][tokenType].length();
    }

    function ownerOf(uint256 tokenId, uint256 tokenType) internal view returns (address owner) {
        return gs().battleflyOwner[tokenId][tokenType];
    }
}

