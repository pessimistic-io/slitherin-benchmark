// SPDX-License-Identifier: ISC

pragma solidity ^0.8.0;

interface IRegistry {
    function triggerServer() external view returns (address);
    function usdt() external view returns (address);
    function feeder() external view returns (address);
    function interaction() external view returns (address);
    function fees() external view returns (address);
    function tradeBeacon() external view returns (address);
    function dripOperator() external view returns (address);
    function ethPriceFeed() external view returns (address);
    function tradeUpgrader() external view returns (address);
    function whitelist() external view returns (address);
    function tradeParamsUpdater() external view returns (address);
    function killSwitch() external view returns (address);
    function upgrader() external view returns (address);
    function swapper() external view returns (address);
    function aavePoolDataProvider() external view returns (address);
    function aavePool() external view returns (address);
    function gmxVault() external view returns (address);
    function gmxRouter() external view returns (address);
    function gmxPositionRouter() external view returns (address);
}

