// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IOracle {
    function getUnderlyingPrice(
        string memory _pair
    ) external view returns (uint256);
}

