//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {IERC20} from "./ERC20.sol";

interface IMiniChefV2 {
    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of SUSHI entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each MCV2 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of SUSHI to distribute per block.
    struct PoolInfo {
        uint128 accSushiPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
    }

    // /// @notice Address of SUSHI contract.
    // IERC20 external immutable SUSHI;

    // /// @notice Info of each MCV2 pool.
    // PoolInfo[] external poolInfo;

    // /// @notice Address of the LP token for each MCV2 pool.
    // IERC20[] external lpToken;

    // /// @notice Info of each user that stakes LP tokens.
    // mapping(uint256 => mapping(address => UserInfo)) external userInfo;
    // /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    // uint256 external totalAllocPoint;

    // uint256 external sushiPerSecond;
    // uint256 private constant ACC_SUSHI_PRECISION = 1e12;

    /// @notice Returns the number of MCV2 pools.
    function poolLength() external view returns (uint256 pools);

    /// @notice View function to see pending SUSHI on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending SUSHI reward for a given user.
    function pendingSushi(
        uint256 _pid,
        address _user
    ) external view returns (uint256 pending);

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) external returns (PoolInfo memory pool);

    /// @notice Deposit LP tokens to MCV2 for SUSHI allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(uint256 pid, uint256 amount, address to) external;

    /// @notice Withdraw LP tokens from MCV2.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(uint256 pid, uint256 amount, address to) external;

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of SUSHI rewards.
    function harvest(uint256 pid, address to) external;

    /// @notice Withdraw LP tokens from MCV2 and harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and SUSHI rewards.
    function withdrawAndHarvest(
        uint256 pid,
        uint256 amount,
        address to
    ) external;

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) external;
}

