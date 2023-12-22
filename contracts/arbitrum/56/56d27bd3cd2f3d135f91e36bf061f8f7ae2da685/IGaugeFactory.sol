// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IGaugeFactory {
    function createGauge(address _pair, address _bribe, address _ve) external returns (address);
}
