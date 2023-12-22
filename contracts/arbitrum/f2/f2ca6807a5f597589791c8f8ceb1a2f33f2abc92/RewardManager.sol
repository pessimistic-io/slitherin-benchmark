// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { SafeCast } from "./SafeCast.sol";
import { FixedPointMathLib } from "./FixedPointMathLib.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

/**
 * @dev RewardManager.sol is a modified version of Pendle's RewardManager.sol & RewardManagerAbstract:
 * https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/core/RewardManager/RewardManager.sol
 *
 * @notice
 * This is used with FactorGauge. RewardManager must not have duplicated rewardTokens
 */

abstract contract RewardManager {
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    struct RewardState {
        uint128 index;
        uint128 lastBalance;
    }

    struct UserReward {
        uint128 index;
        uint128 accrued;
    }

    struct RewardManagerStorage {
        uint256 lastRewardBlock;
        /// @dev [token] => [user] => (index, accrued)
        mapping(address => mapping(address => UserReward)) userReward;
        /// @dev [token] => (index, lastBalance)
        mapping(address => RewardState) rewardState;
    }

    bytes32 private constant REWARD_MANAGER_STORAGE = keccak256('factor.base.RewardManager.storage');

    function _getRewardManagerStorage() internal pure returns (RewardManagerStorage storage $) {
        bytes32 slot = REWARD_MANAGER_STORAGE;
        assembly {
            $.slot := slot
        }
    }

    uint256 internal constant INITIAL_REWARD_INDEX = 1;

    function _updateAndDistributeRewards(address user) internal virtual {
        _updateAndDistributeRewardsForTwo(user, address(0));
    }

    function _updateAndDistributeRewardsForTwo(address user1, address user2) internal virtual {
        (address[] memory tokens, uint256[] memory indexes) = _updateRewardIndex();
        if (tokens.length == 0) return;

        if (user1 != address(0) && user1 != address(this)) _distributeRewardsPrivate(user1, tokens, indexes);
        if (user2 != address(0) && user2 != address(this)) _distributeRewardsPrivate(user2, tokens, indexes);
    }

    /**
     * @dev should only be callable from `_updateAndDistributeRewardsForTwo` to guarantee
     * user != address(0) && user != address(this)
     */
    function _distributeRewardsPrivate(address user, address[] memory tokens, uint256[] memory indexes) private {
        assert(user != address(0) && user != address(this));

        RewardManagerStorage storage $ = _getRewardManagerStorage();

        uint256 userShares = _rewardSharesUser(user);

        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            uint256 index = indexes[i];
            uint256 userIndex = $.userReward[token][user].index;

            if (userIndex == 0) {
                $.userReward[token][user].index = index.toUint128();
                continue;
            }

            if (userIndex == index) continue;

            uint256 deltaIndex = index - userIndex;
            uint256 rewardDelta = userShares.mulWadDown(deltaIndex);
            uint256 rewardAccrued = $.userReward[token][user].accrued + rewardDelta;

            $.userReward[token][user] = UserReward({ index: index.toUint128(), accrued: rewardAccrued.toUint128() });
        }
    }

    function _updateRewardIndex() internal virtual returns (address[] memory tokens, uint256[] memory indexes) {
        tokens = _getRewardTokens();
        indexes = new uint256[](tokens.length);

        if (tokens.length == 0) return (tokens, indexes);

        RewardManagerStorage storage $ = _getRewardManagerStorage();

        if ($.lastRewardBlock != block.number) {
            // if we have not yet update the index for this block
            $.lastRewardBlock = block.number;

            uint256 totalShares = _rewardSharesTotal();

            _redeemExternalReward();

            for (uint256 i = 0; i < tokens.length; ++i) {
                address token = tokens[i];

                // the entire token balance of the contract must be the rewards of the contract
                uint256 accrued = IERC20(tokens[i]).balanceOf(address(this)) - $.rewardState[token].lastBalance;
                uint256 index = $.rewardState[token].index;

                if (index == 0) index = INITIAL_REWARD_INDEX;
                if (totalShares != 0) index += accrued.divWadDown(totalShares);

                $.rewardState[token].index = index.toUint128();
                $.rewardState[token].lastBalance += accrued.toUint128();
            }
        }

        for (uint256 i = 0; i < tokens.length; i++) indexes[i] = $.rewardState[tokens[i]].index;
    }

    /// @dev this function doesn't need redeemExternal since redeemExternal is bundled in updateRewardIndex
    /// @dev this function also has to update rewardState.lastBalance
    function _doTransferOutRewards(
        address user,
        address receiver
    ) internal virtual returns (uint256[] memory rewardAmounts) {
        address[] memory tokens = _getRewardTokens();
        rewardAmounts = new uint256[](tokens.length);

        RewardManagerStorage storage $ = _getRewardManagerStorage();

        for (uint256 i = 0; i < tokens.length; i++) {
            rewardAmounts[i] = $.userReward[tokens[i]][user].accrued;
            if (rewardAmounts[i] != 0) {
                $.userReward[tokens[i]][user].accrued = 0;
                $.rewardState[tokens[i]].lastBalance -= rewardAmounts[i].toUint128();
                IERC20(tokens[i]).safeTransfer(receiver, rewardAmounts[i]);
            }
        }
    }

    function _redeemExternalReward() internal virtual;

    function _rewardSharesUser(address user) internal view virtual returns (uint256);

    function _getRewardTokens() internal view virtual returns (address[] memory);

    function _rewardSharesTotal() internal view virtual returns (uint256);

    function getLastRewardBlock() external view returns (uint256) {
        return _getRewardManagerStorage().lastRewardBlock;
    }

    function _calculateReward(address user, address token, uint256 accumulatedFctr) internal view returns (uint256) {
        RewardManagerStorage storage $ = _getRewardManagerStorage();

        uint256 index = $.rewardState[token].index;
        if (index == 0) index = INITIAL_REWARD_INDEX;

        uint256 totalShares = _rewardSharesTotal();
        if (totalShares != 0) index += accumulatedFctr.divWadDown(totalShares);

        uint256 userIndex = $.userReward[token][user].index;
        uint256 rewardDelta = _rewardSharesUser(user).mulWadDown(index - userIndex);

        uint256 rewardAccrued = $.userReward[token][user].accrued + rewardDelta;

        return rewardAccrued;
    }
}

