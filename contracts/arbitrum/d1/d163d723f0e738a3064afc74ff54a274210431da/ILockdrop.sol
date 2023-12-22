// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {IERC20} from "./IERC20.sol";

/**
 * @title ILockdrop
 * @notice  The purpose of the Lockdrop contract is to provide liquidity to the newly created dex by collecting funds from users
 */
interface ILockdrop {
    error WrongAllocationState(
        AllocationState current,
        AllocationState expected
    );

    error TimestampsIncorrect();
    error PairAlreadyCreated();

    enum AllocationState {
        NOT_STARTED,
        ALLOCATION_ONGOING,
        ALLOCATION_FINISHED
    }

    /**
     * @notice Function allows the authorized wallet to add liquidity on SpartaDEX router.
     * @param router_ Address of SpartaDexRouter.
     * @param deadline_ Deadline by which liquidity should be added.
     */
    function addTargetLiquidity(
        IUniswapV2Router02 router_,
        uint256 deadline_
    ) external;

    /**
     * @notice Function returns the newly created SpartaDexRouter.
     * @return IUniswapV2Router02 Address of the router.
     */
    function spartaDexRouter() external view returns (IUniswapV2Router02);

    /**
     * @notice Function returns the timestamp of the lockdrop start.
     * @return uint256 Start timestamp.
     */
    function lockingStart() external view returns (uint256);

    /**
     * @notice Function returns the timestamp of the lockdrop end.
     * @return uint256 End Timestamp.
     */
    function lockingEnd() external view returns (uint256);

    /**
     * @notice Function returns the timestamp of the unlocking period end.
     * @return uint256 The ending timestamp.
     */
    function unlockingEnd() external view returns (uint256);

    /**
     * @notice Function returns the amount of the tokens that correspond to the provided liquidity on SpartaDex.
     * @return uint256 Amount of LP tokens.
     */
    function initialLpTokensBalance() external view returns (uint256);

    /**
     * @notice Function returns the total reward for the lockdrop.
     * @return uint256 Total amount of reward.
     */
    function totalReward() external view returns (uint256);

    /**
     * @notice Function returns the exchange pair address for the lockdrop.
     * @return IUniswapV2Pair Address of token created on the target DEX.
     */
    function exchangedPair() external view returns (address);

    /**
     * @notice Function returns the reward of the lockdrop
     * @return IERC20 Address
     *  of reward token.
     */
    function rewardToken() external view returns (IERC20);

    /**
     * @notice Function returns time from which funds can be withdrawn if migration has not taken place.
     * @return uint256 Migration start timestamp.
     */
    function migrationEndTimestamp() external view returns (uint256);
}

