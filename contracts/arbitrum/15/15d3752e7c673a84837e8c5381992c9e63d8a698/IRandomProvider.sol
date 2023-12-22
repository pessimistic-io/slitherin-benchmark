// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ChainlinkVRFV2Randomiser} from "./ChainlinkVRFV2Randomiser.sol";

interface IRandomProvider {
    /// @notice Compute the required ETH to get a random number
    /// @param callbackGasLimit Gas limit to use for callback
    function computeRandomNumberRequestCost(uint32 callbackGasLimit)
        external
        returns (uint256);

    /// @notice Get a random number from
    /// @param callbackGasLimit Gas limit to use for callback
    /// @param minBlocksToWait Minimum confirmations to wait
    function getRandomNumber(uint32 callbackGasLimit, uint16 minBlocksToWait)
        external
        payable
        returns (uint256 requestId);
}

