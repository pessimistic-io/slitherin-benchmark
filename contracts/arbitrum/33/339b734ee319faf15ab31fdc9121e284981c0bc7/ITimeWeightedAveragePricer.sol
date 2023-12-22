// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "./ERC20_IERC20.sol";
import { ISnapshottable } from "./ISnapshottable.sol";

interface ITimeWeightedAveragePricer is ISnapshottable {
    function token0() external view returns (IERC20);
    function token1() external view returns (IERC20);

    /**
     * @dev Calculates the current price based on the stored samples.
     * @return The current price as a uint256.
     */
    function calculateToken0Price() external view returns (uint256);

    /**
     * @dev Returns the current price of token0, denominated in token1.
     * @return The current price as a uint256.
     */
    function getToken0Price() external view returns (uint256);

    /**
     * @dev Returns the current price of token1, denominated in token0.
     * @return The current price as a uint256.
     */
    function getToken1Price() external view returns (uint256);

    function getToken0Value(uint256 amount) external view returns (uint256);
    function getToken0ValueAtSnapshot(uint256 _blockNumber, uint256 amount) external view returns (uint256);

    function getToken1Value(uint256 amount) external view returns (uint256);

    /**
     * @dev Returns the block number of the oldest sample.
     * @return The block number of the oldest sample as a uint256.
     */
    function getOldestSampleBlock() external view returns (uint256);

    /**
     * @dev Returns the current price if the oldest sample is still considered fresh.
     * @return The current price as a uint256.
     */
    function getToken0FreshPrice() external view returns (uint256);

    /**
     * @dev Returns the current price if the oldest sample is still considered fresh.
     * @return The current price as a uint256.
     */
    function getToken1FreshPrice() external view returns (uint256);

    /**
     * @dev Returns the next sample index given the current index and sample count.
     * @param i The current sample index.
     * @param max The maximum number of samples.
     * @return The next sample index as a uint64.
     */
    function calculateNext(uint64 i, uint64 max) external pure returns (uint64);

    /**
     * @dev Returns the previous sample index given the current index and sample count.
     * @param i The current sample index.
     * @param max The maximum number of samples.
     * @return The previous sample index as a uint64.
     */
    function calculatePrev(uint64 i, uint64 max) external pure returns (uint64);

    /**
     * @dev Samples the current spot price of the token pair from all pools.
     * @return A boolean indicating whether the price was sampled or not.
     */
    function samplePrice() external returns (bool);

    /**
     * @dev Samples the current spot price of the token pair from all pools, throwing if the previous sample was too recent.
     */
    function enforcedSamplePrice() external;

    /**
     * @dev Calculates the spot price of the token pair from all pools.
     * @return The spot price as a uint256.
     */
    function calculateToken0SpotPrice() external view returns (uint256);
}

