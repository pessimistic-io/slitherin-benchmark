// SPDX-License-Identifier: UNLICENSED

pragma solidity >= 0.8.0;

/**
 * @title ITradingIncentiveController
 * @author LevelFinance
 * @notice Tracking protocol fee and calculate incentive reward in a period of time called batch.
 * Once a batch finished, incentive distributed to lyLVL and Ladder
 */
interface ITradingIncentiveController {
    /**
     * @notice record trading fee collected in batch. Call by PoolHook only
     * @param _value trading generated. Includes swap and leverage trading
     */
    function record(uint256 _value) external;

    /**
     * @notice start tracking fee and calculate. Called only once by owner
     */
    function start(uint256 _startTime) external;

    /**
     * @notice finalize current batch and distribute rewards
     */
    function allocate() external;
}

