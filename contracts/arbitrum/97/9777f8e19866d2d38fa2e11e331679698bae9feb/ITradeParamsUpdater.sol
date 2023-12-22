// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITradeParamsUpdater {
    function nearestUpdate(address _destination) external view returns (uint256);
}
