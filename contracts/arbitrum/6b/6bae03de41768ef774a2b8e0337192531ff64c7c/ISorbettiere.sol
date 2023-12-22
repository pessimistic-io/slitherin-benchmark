//SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./IERC20.sol";

interface ISorbettiere {
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 remainingIceTokenReward;
    }

    struct PoolInfo {
        IERC20 stakingToken;
        uint256 stakingTokenTotalAmount;
        uint256 accIcePerShare;
        uint32 lastRewardTime;
        uint16 allocPoint;
    }

    /// @notice Deposit staking tokens to Sorbettiere for ICE allocation.
    function deposit(uint256 pid, uint256 amount) external;

    /// @notice Withdraw staked tokens from Sorbettiere.
    function withdraw(uint256 pid, uint256 amount) external;

    /// @notice Info of each user.
    function userInfo(
        uint256 pid,
        address user
    ) external view returns (UserInfo memory);

    /**
     * @notice View function to see pending ICE.
     *         stakingToken - How many LP tokens the user has provided.
     *         rewardDebt -  Reward debt. See explanation below.
     *         remainingIceTokenReward - ICE Tokens that weren't distributed
     *         for user per pool.
     */
    function pendingIce(
        uint256 pid,
        address user
    ) external view returns (uint256);

    /**
     * @notice View function to see info of each pool.
     *         amount - How many LP tokens the user has provided.
     *         stakingTokenTotalAmount -  Total amount of deposited tokens.
     *         accIcePerShare - Accumulated ICE per share, times 1e12.
     *                          See below.
     *         lastRewardTime - Last timestamp number that ICE distribution
     *                          occurs.
     *         allocPoint - How many allocation points assigned to this pool.
     *                      ICE to distribute per second.
     */
    function poolInfo(uint256 pid) external view returns (PoolInfo memory);

    /// @notice Time on which the reward calculation should end
    function endTime() external view returns (uint256);

    /// @notice Ice tokens vested per second.
    function icePerSecond() external view returns (uint256);

    /// @notice Total allocation poitns. Must be the sum of all allocation
    ///         points in all pools.
    function totalAllocPoint() external view returns (uint256);
}

