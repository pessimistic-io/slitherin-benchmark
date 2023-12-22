// SPDX-License-Identifier: GPLv2
pragma solidity ^0.8.1;

interface IPixelMushrohmStaking {
    /* ========== EVENTS ========== */

    event Staked(uint256 tokenId);
    event Unstaked(uint256 tokenId);
    event PixelMushrohmSet(address pixelMushrohm);

    /* ========== STRUCTS ========== */

    struct StakedTokenData {
        uint256 timestampStake;
        uint256 timestampLevel;
    }

    /* ======== ADMIN FUNCTIONS ======== */

    function setPixelMushrohm(address _pixelMushrohm) external;

    function setPaymentToken(address _tokenAddr) external;

    function setStakingPrice(uint256 _price) external;

    function setLevelUpPrice(uint256 _price) external;

    function inPlaceSporePowerUpdate(uint256 _tokenId) external;

    function withdraw(address _tokenAddr) external;

    /* ======== MUTABLE FUNCTIONS ======== */

    function stake(uint256 _tokenId) external;

    function unstake(uint256 _tokenId) external;

    function levelUp(uint256 _tokenId) external;

    /* ======== VIEW FUNCTIONS ======== */

    function getPaymentToken() external view returns (address);

    function getStakingPrice() external view returns (uint256);

    function getLevelUpPrice() external view returns (uint256);

    function sporePowerEarned(uint256 _tokenId) external view returns (uint256);

    function levelPowerEarned(uint256 _tokenId) external view returns (uint256);

    function levelPerWeek(uint256 _tokenId) external view returns (uint256);

    function isStaked(uint256 _tokenId) external view returns (bool);

    function isEligibleForLevelUp(uint256 _tokenId) external view returns (bool);
}

