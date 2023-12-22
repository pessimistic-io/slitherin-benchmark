// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4;

interface IStrategy {
    function name() external pure returns (string memory);

    function getThreshold(
        address ref,
        uint256 thresholdParameter,
        uint256 blockNumber
    ) external view returns (uint256);

    function getPastVotes(
        address ref,
        address account,
        uint256 blockNumber
    ) external view returns (uint256);
}

