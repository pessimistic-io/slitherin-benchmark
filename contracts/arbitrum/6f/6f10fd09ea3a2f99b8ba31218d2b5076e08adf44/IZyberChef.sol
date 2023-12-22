// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IBoringERC20} from "./IBoringERC20.sol";
import {IMultipleRewards} from "./IMultipleRewards.sol";

interface IZyberChef {
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardLockedUp; // Reward locked up.
        uint256 nextHarvestUntil; // When can the user harvest again.
    }

    // Info of each pool.
    struct PoolInfo {
        IBoringERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Zyber to distribute per block.
        uint256 lastRewardTimestamp; // Last block number that Zyber distribution occurs.
        uint256 accZyberPerShare; // Accumulated Zyber per share, times 1e18. See below.
        uint16 depositFeeBP; // Deposit fee in basis points
        uint256 harvestInterval; // Harvest interval in seconds
        uint256 totalLp; // Total token in Pool
        IMultipleRewards[] rewarders; // Array of rewarder contract for pools with incentives
    }

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function pendingTokens(
        uint256 _pid,
        address _user
    )
        external
        view
        returns (
            address[] memory addresses,
            string[] memory symbols,
            uint256[] memory decimals,
            uint256[] memory amounts
        );

    function userInfo(
        uint256 _pid,
        address _user
    )
        external
        view
        returns (
            uint256 amount,
            uint256 rewardDebt,
            uint256 rewardLockedUp,
            uint256 nextHarvestUntil
        );
}

