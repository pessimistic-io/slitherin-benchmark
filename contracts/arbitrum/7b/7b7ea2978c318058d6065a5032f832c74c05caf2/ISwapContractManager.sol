// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

interface ISwapContractManager {
    function updateSwapContractNotionalValue(uint256, uint256, uint256) external;
}
