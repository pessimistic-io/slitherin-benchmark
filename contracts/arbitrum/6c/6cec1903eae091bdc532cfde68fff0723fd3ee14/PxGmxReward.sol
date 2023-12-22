// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Owned} from "./Owned.sol";
import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";

contract PxGmxReward is Owned {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    struct User {
        // User index
        uint256 index;
        // Accrued but not yet transferred rewards
        uint256 rewardsAccrued;
    }

    // The fixed point factor
    uint256 public constant ONE = 1e18;

    // pxGmx token
    ERC20 public immutable pxGmx;

    // Strategy index (ie. pxGmx)
    uint256 public strategyIndex;

    // User data
    mapping(address => User) internal users;

    event AccrueStrategy(uint256 accruedRewards);
    event AccrueRewards(
        address indexed user,
        uint256 rewardsDelta,
        uint256 rewardsIndex
    );
    event PxGmxClaimed(address indexed account, uint256 amount);

    error ZeroAddress();

    /**
        @param  _pxGmx  address  pxGMX token address
     */
    constructor(address _pxGmx) Owned(msg.sender) {
        if (_pxGmx == address(0)) revert ZeroAddress();

        pxGmx = ERC20(_pxGmx);
    }

    /**
      @notice Sync strategy index with the rewards
      @param  accruedRewards  uint256  The rewards amount accrued by the strategy
      @param  supplyTokens    uint256  Total supply of the strategy token
    */
    function _accrueStrategy(uint256 accruedRewards, uint256 supplyTokens)
        internal
    {
        emit AccrueStrategy(accruedRewards);

        if (accruedRewards == 0) return;

        uint256 deltaIndex;

        if (supplyTokens != 0)
            deltaIndex = accruedRewards.mulDivDown(ONE, supplyTokens);

        // Accumulate rewards per token onto the index, multiplied by fixed-point factor
        strategyIndex += deltaIndex;
    }

    /**
      @notice Sync user state with strategy
      @param  user  address  The user to accrue rewards for
    */
    function _accrueUser(address user) internal {
        User storage u = users[user];

        // Load indices
        uint256 _strategyIndex = strategyIndex;
        uint256 supplierIndex = u.index;

        // Sync user index to global
        u.index = _strategyIndex;

        uint256 deltaIndex = _strategyIndex - supplierIndex;

        // Accumulate rewards by multiplying user tokens by rewardsPerToken index and adding on unclaimed
        uint256 supplierDelta = ERC20(address(this)).balanceOf(user).mulDivDown(
            deltaIndex,
            ONE
        );
        uint256 supplierAccrued = u.rewardsAccrued + supplierDelta;

        u.rewardsAccrued = supplierAccrued;

        emit AccrueRewards(user, supplierDelta, _strategyIndex);
    }

    /**
        @notice Get a strategy index for a user
        @param  user  address  User
     */
    function getUserIndex(address user) external view returns (uint256) {
        return users[user].index;
    }

    /**
        @notice Get the rewards accrued for a user
        @param  user  address  User
     */
    function getUserRewardsAccrued(address user)
        external
        view
        returns (uint256)
    {
        return users[user].rewardsAccrued;
    }

    function _claim(address user) internal {
        // Process extra rewards (eg. pxGMX) and claim for the user
        User storage u = users[user];
        uint256 accrued = u.rewardsAccrued;

        if (accrued != 0) {
            u.rewardsAccrued = 0;

            pxGmx.safeTransfer(user, accrued);

            emit PxGmxClaimed(user, accrued);
        }
    }
}

