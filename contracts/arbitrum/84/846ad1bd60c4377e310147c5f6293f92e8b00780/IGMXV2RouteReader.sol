// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IGMXPosition} from "./IGMXPosition.sol";

import {OrderUtils} from "./OrderUtils.sol";

/// @title IGMXV2RouteReader
/// @dev Interface for GMXV2RouteReader contract
interface IGMXV2RouteReader {
    function isWaitingForCallback(bytes32 _routeKey) external view returns (bool);
    function getCreateOrderParams(uint256 _sizeDelta, uint256 _collateralDelta, uint256 _acceptablePrice, uint256 _executionFee, address _route, bool _isIncreaseBool) external view returns (OrderUtils.CreateOrderParams memory _params);
    function gmxRouter() external view returns (address);
    function gmxExchangeRouter() external view returns (address);
    function gmxOrderVault() external view returns (address);
}
