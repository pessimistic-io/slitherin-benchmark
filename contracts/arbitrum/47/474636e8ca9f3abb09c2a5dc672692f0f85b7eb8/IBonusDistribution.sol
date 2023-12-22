// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ITokenTransferProxy.sol";

interface IBonusDistribution {
    enum BonusState { Undefined, Pending, Active, Completed, Released } // Enum

    struct BonusPortion {
        uint8 id;
        BonusState state;
        address tokenAdd;
        uint256 amount;
        uint256 released;
        uint256 progress;
        uint256 progressTarget;
    }

    struct CombinedBonusData {
        uint8 numPortions;
        uint8 currentPortion;
        uint256 claimedBonus;
        uint256 addedBonus;
        uint256 releasedBonus;
        BonusPortion[] portions;
    }

    struct UserBonusData {
        uint256 progress;
        uint256 availableBonus;
    }

    function addPortion(uint8 id, address tokenAdd, uint256 amount, uint256 target) external;
    function claimBonus(address tokenAdd) external;
    function updateProgress(address inAccount, uint256 inNewProgress) external;
    function releaseBonus(address[] calldata inRecipients) external;
    function setPortionState(uint8 inId, BonusState inState) external;
    function getPortion(uint8 id) external view returns (BonusPortion memory);
    function getCombinedData(address tokenAdd) external view returns (CombinedBonusData memory);
    function getUserData(address inAccount, address tokenAdd) external view returns (UserBonusData memory);
}

