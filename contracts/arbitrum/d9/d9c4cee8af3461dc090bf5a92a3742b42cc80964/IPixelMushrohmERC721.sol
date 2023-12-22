// SPDX-License-Identifier: GPLv2
pragma solidity ^0.8.1;

import "./extensions_IERC721Enumerable.sol";

interface IPixelMushrohmERC721 is IERC721Enumerable {
    /* ========== EVENTS ========== */

    event PixelMushrohmMint(address to, uint256 tokenId);
    event RedeemSporePower(uint256 tokenId, uint256 amount);
    event SporePowerCost(uint256 sporePowerCost);
    event MaxSporePowerLevel(uint256 maxSporePowerLevel);
    event LevelCost(uint256 levelCost);
    event MaxLevel(uint256 maxLevel);
    event BaseLevelMultiplier(uint256 levelMultiplier);
    event AdditionalMultiplier(uint256 tokenId, uint256 multiplier);
    event FirstGenLevelMintLevel(uint256 level);
    event StakingSet(address staking);
    event RedeemerAdded(address redeemer);
    event RedeemerRemoved(address redeemer);
    event MultiplierAdded(address multiplier);
    event MultiplierRemoved(address multiplier);
    event BridgeSet(address bridge);

    /* ========== ENUMS ========== */

    enum MintType {
        APELIEN_AIRDROP,
        NOOSH_AIRDROP,
        PILOT_AIRDROP,
        R3L0C_AIRDROP,
        MEMETIC_AIRDROP,
        BRIDGE,
        STANDARD
    }

    /* ========== STRUCTS ========== */

    struct TokenData {
        uint256 sporePower;
        uint256 sporePowerPerWeek;
        uint256 level;
        uint256 levelPower;
        uint256 additionalMultiplier;
    }

    /* ======== ADMIN FUNCTIONS ======== */

    function setStaking(address _staking) external;

    function addRedeemer(address _redeemer) external;

    function removeRedeemer(address _redeemer) external;

    function addMultiplier(address _multiplier) external;

    function removeMultiplier(address _multiplier) external;

    function setBridge(address _bridge) external;

    function setMaxSporePowerLevel(uint256 _max) external;

    function setMaxLevel(uint256 _max) external;

    function setBaseLevelMultiplier(uint256 _multiplier) external;

    function setFirstGenLevelMintLevel(uint256 _level) external;

    function setSporePowerPerWeek(uint256 _sporePowerPerWeek, uint256[] calldata _tokenIds) external;

    function setBaseURI(string memory _baseURItoSet) external;

    function setPrerevealURI(string memory _prerevealURI) external;

    function setMintToken(address _tokenAddr) external;

    function setMintTokenPrice(uint256 _price) external;

    function setMaxMintPerWallet(uint256 _maxPerWallet) external;

    function setMerkleRoot(bytes32 _merkleRoot) external;

    function toggleReveal() external;

    function withdraw(address _tokenAddr) external;

    function manualBridgeMint(address[] calldata _to, uint256[] calldata _tokenId) external;

    function airdrop(
        MintType _mintType,
        address[] calldata _to,
        uint256[] calldata _amount
    ) external;

    /* ======== MUTABLE FUNCTIONS ======== */

    function whitelistMint(uint256 _amount, bytes32[] calldata _merkleProof) external;

    function bridgeMint(address _to, uint256 _tokenId) external;

    function firstGenLevelMint(uint256 _tokenId) external;

    function updateSporePower(uint256 _tokenId, uint256 _sporePowerEarned) external;

    function updateLevelPower(uint256 _tokenId, uint256 _levelPowerEarned) external;

    function updateLevel(uint256 _tokenId) external;

    function redeemSporePower(uint256 _tokenId, uint256 _amount) external;

    function setAdditionalMultiplier(uint256 _tokenId, uint256 _multiplier) external;

    /* ======== VIEW FUNCTIONS ======== */

    function exists(uint256 _tokenId) external view returns (bool);

    function getMintToken() external view returns (address);

    function getMintTokenPrice() external view returns (uint256);

    function getMaxMintPerWallet() external view returns (uint256);

    function getSporePower(uint256 _tokenId) external view returns (uint256);

    function getSporePowerLevel(uint256 _tokenId) external view returns (uint256);

    function averageSporePower() external view returns (uint256);

    function getSporePowerCost() external view returns (uint256);

    function getMaxSporePowerLevel() external view returns (uint256);

    function getSporePowerPerWeek(uint256 _tokenId) external view returns (uint256);

    function getLevel(uint256 _tokenId) external view returns (uint256);

    function getLevelPower(uint256 _tokenId) external view returns (uint256);

    function getLevelCost() external view returns (uint256);

    function getMaxLevel() external view returns (uint256);

    function getBaseLevelMultiplier() external view returns (uint256);

    function getLevelMultiplier(uint256 _tokenId) external view returns (uint256);

    function getAdditionalMultiplier(uint256 _tokenId) external view returns (uint256);

    function getTokenURIsForOwner(address _owner) external view returns (string[] memory);

    function isEligibleForLevelMint(uint256 _tokenId) external view returns (bool);

    function getNumTokensMinted(address _owner) external view returns (uint256);

    function isSporePowerMaxed(uint256 _tokenId) external view returns (bool);

    function isLevelPowerMaxed(uint256 _tokenId) external view returns (bool);

    function isLevelMaxed(uint256 _tokenId) external view returns (bool);

    function hasUserHitMaxMint(address _user) external view returns (bool);
}

