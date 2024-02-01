// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRandomConsumer {
    function runFulfillRandomness(uint256 tokenId_, address user_, uint256 randomness_) external;
}
