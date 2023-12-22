// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IBattleflyAtlasStakerV02.sol";
import "./IAtlasMine.sol";
import "./ICreatureOwnerResolverRegistry.sol";

interface ISmoloveActionsVault {
    // ============================================ EVENT ==============================================
    event Stake(address indexed user, uint256 stakeId, uint256 amount, uint256 inclusion);
    event Withdraw(address indexed user, uint256 stakeId, uint256 amount);
    event RequestWithdrawal(uint256 stakeId);
    event SetAdminAccess(address indexed user, bool access);
    event ClaimAndRestake(uint256 amount);

    struct UserStake {
        uint256 id;
        uint256 amount;
        uint256 inclusion;
        uint256 withdrawAt;
        address owner;
    }

    struct AtlasStake {
        uint256 id;
        uint256 amount;
        uint256 withdrawableAt;
        uint256 startDay;
    }

    function stake(address user, uint256 amount) external;

    function getStakeAmount(address user) external view returns (uint256);

    function getTotalClaimableAmount() external view returns (uint256);

    function getUserStakes(address user) external view returns (UserStake[] memory);

    function withdrawAll() external;

    function withdraw(uint256[] memory stakeIds) external;

    function requestWithdrawal(uint256[] memory stakeIds) external;

    function claimAllAndRestake(uint256 index,
        uint256 epoch,
        uint256 cumulativeFlywheelAmount,
        uint256 cumulativeHarvesterAmount,
        uint256 flywheelClaimableAtEpoch,
        uint256 harvesterClaimableAtEpoch,
        uint256 individualMiningPower,
        uint256 totalMiningPower,
        bytes32[] calldata merkleProof) external;

    function canRequestWithdrawal(uint256 stakeId) external view returns (bool requestable);

    function canWithdraw(uint256 stakeId) external view returns (bool withdrawable);

    function initialUnlock(uint256 stakeId) external view returns (uint256 epoch);

    function retentionUnlock(uint256 stakeId) external view returns (uint256 epoch);

    function getCurrentEpoch() external view returns (uint256 epoch);

    function getNumberOfActiveStakes() external view returns (uint256 amount);
}

