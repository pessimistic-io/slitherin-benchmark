// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IERC20Decimals} from "./IERC20Decimals.sol";
import {ILockdrop, IUniswapV2Router02} from "./ILockdrop.sol";
import {IAccessControl, IAccessControlHolder} from "./IAccessControlHolder.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {ZeroAddressGuard} from "./ZeroAddressGuard.sol";
import {ZeroAmountGuard} from "./ZeroAmountGuard.sol";

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";

/**
 * @title Lockdrop
 * @notice This contract is base implementation of common lockdrop functionalities.
 */
abstract contract Lockdrop is
    ILockdrop,
    IAccessControlHolder,
    ZeroAddressGuard,
    ZeroAmountGuard
{
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public override spartaDexRouter;
    IAccessControl public immutable override acl;
    IERC20 public immutable override rewardToken;
    uint256 public override initialLpTokensBalance;
    uint256 public immutable override lockingStart;
    uint256 public immutable override migrationEndTimestamp;
    uint256 public immutable override lockingEnd;
    uint256 public immutable override unlockingEnd;
    uint256 public immutable override totalReward;

    /**
     * @notice Modifier verifies that the current allocation state equals the expected state.
     * @dev Modifier reverts with WrongAllocationState, when the current state is different than expected.
     * @param expected Expected state of lockdrop.
     */
    modifier onlyOnAllocationState(AllocationState expected) {
        AllocationState current = _allocationState();
        if (current != expected) {
            revert WrongAllocationState(current, expected);
        }
        _;
    }

    constructor(
        IAccessControl _acl,
        IERC20 _rewardToken,
        uint256 _lockingStart,
        uint256 _lockingEnd,
        uint256 _unlockingEnd,
        uint256 _migrationEndTimestamp,
        uint256 _totalReward
    ) notZeroAmount(_totalReward) {
        acl = _acl;
        if (
            block.timestamp > _lockingStart ||
            _lockingStart > _unlockingEnd ||
            _unlockingEnd > _lockingEnd ||
            _lockingEnd > _migrationEndTimestamp
        ) {
            revert TimestampsIncorrect();
        }
        lockingStart = _lockingStart;
        lockingEnd = _lockingEnd;
        unlockingEnd = _unlockingEnd;
        totalReward = _totalReward;
        rewardToken = _rewardToken;
        migrationEndTimestamp = _migrationEndTimestamp;
    }

    /**
     * @notice Function returns the sorted tokens used in the lockdrop.
     * @return (address, address) Sorted addresses of tokens.
     */
    // function _tokens() internal view virtual returns (address, address);

    /**
     * @notice Function returns the current allocation state.
     * @return AllocationState Current AllocationState.
     */
    function _allocationState() internal view returns (AllocationState) {
        if (block.timestamp >= lockingEnd) {
            return AllocationState.ALLOCATION_FINISHED;
        } else if (block.timestamp >= lockingStart) {
            if (rewardToken.balanceOf(address(this)) >= totalReward) {
                return AllocationState.ALLOCATION_ONGOING;
            }
        }

        return AllocationState.NOT_STARTED;
    }
}

