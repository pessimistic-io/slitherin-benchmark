// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ChainlinkVRFV2Randomiser} from "./ChainlinkVRFV2Randomiser.sol";

interface IRandomProvider {
    /// @notice Get a random number from VRF
    /// @param minBlocksToWait Minimum confirmations to wait
    function getRandomNumber(uint16 minBlocksToWait) external returns (uint256);
}

