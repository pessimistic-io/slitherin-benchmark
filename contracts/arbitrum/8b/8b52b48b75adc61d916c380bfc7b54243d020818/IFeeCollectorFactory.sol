// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IFeeCollectorFactory {
    function createFeeCollector(address rainbowRoad, address authorizedAccount) external returns (address);
}
