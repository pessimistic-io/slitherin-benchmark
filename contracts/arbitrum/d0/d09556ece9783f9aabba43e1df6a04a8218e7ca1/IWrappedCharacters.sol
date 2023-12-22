// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC721Metadata.sol";

enum WrappedStatus {NeverWrapped, Wrapped, Unwrapped}
struct Collection {bool native; uint256 range; uint256 offset;}
struct WrappedToken {address collectionAddress; uint256 wrappedTokenID; WrappedStatus status;}
struct Activity {bool active; uint256 numberOfActivities; uint256 activityDuration; uint256 startBlock; uint256 endBlock; uint256 completedBlock;}

abstract contract IWrappedCharacters is IERC721 {
    mapping(bytes32 => uint16[]) public stats;
    mapping (uint256 => Activity) public charactersActivity;
    mapping (bytes32 => WrappedToken) public wrappedToken;
    mapping (uint256 => bytes32) public wrappedTokenHashByID;
    mapping (bytes32 => uint256) public tokenIDByHash;
    mapping(uint256 => uint16) public getStatBoosted;
    function wrap(uint256 wrappedTokenID, address collectionAddress) external virtual;
    function unwrap(uint256 tokenID) external virtual;
    function updateActivityStatus(uint256 tokenID, bool active) external virtual;
    function startActivity(uint256 tokenID, Activity calldata activity) external virtual;
    function setStatTo(uint256 tokenID, uint256 amount, uint256 statIndex) external virtual;
    function increaseStat(uint256 tokenID, uint256 amount, uint256 statIndex) external virtual;
    function decreaseStat(uint256 tokenID, uint256 amount, uint256 statIndex) external virtual;
    function boostStat(uint256 tokenID, uint256 amount, uint256 statIndex)external virtual;
    function getBlocksUntilActivityEnds(uint256 tokenID) external virtual view returns (uint256 blocksRemaining);
    function getMaxHealth(uint256 tokenID) external virtual view returns (uint256 health);
    function getStats(uint256 tokenID) external virtual view returns (uint256 stamina, uint256 strength, uint256 speed, uint256 courage, uint256 intelligence, uint256 health, uint256 morale, uint256 experience, uint256 level);
    function getLevel(uint256 tokenID) external virtual view returns (uint256 level);
    function hashWrappedToken(address collectionAddress, uint256 wrappedTokenID) external virtual pure returns (bytes32 wrappedTokenHash);
    function isWrapped(address collectionAddress, uint256 wrappedTokenID) external virtual view returns (bool tokenExists);
    function getWrappedTokenDetails(uint256 tokenID) external virtual view returns (address collectionAddress, uint256 wrappedTokenID, WrappedStatus status);
}
