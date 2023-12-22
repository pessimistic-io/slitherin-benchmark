// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

interface IRole {
    // functions
    function setDistributionProvider(address, bool) external;

    function setLiquidationProvider(address, bool) external;

    function isDistributionProvider(address) external view returns (bool);

    function isLiquidationProvider(address) external view returns (bool);
    
    // events
    event DistributionProvider(address indexed user, bool status);

    event LiquidationProvider(address indexed user, bool status);
}
