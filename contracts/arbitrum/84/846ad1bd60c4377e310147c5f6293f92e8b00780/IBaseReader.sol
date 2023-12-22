// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ====================== IBaseReader ===========================
// ==============================================================

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

/// @title IBaseReader
/// @dev Interface for BaseReader contract
interface IBaseReader {

    // global

    function precision() external pure returns (uint256);
    function withdrawalFeePercentage() external view returns (uint256);
    function managementFeePercentage() external view returns (uint256);
    function basisPointsDivisor() external pure returns (uint256);
    function collateralTokenDecimals(address _token) external view returns (uint256);
    function platformFeeRecipient() external view returns (address);
    function wnt() external view returns (address);
    function keeper() external view returns (address);
    function isPaused() external view returns (bool);
    function isCollateralToken(address _token) external view returns (bool);
    function isRouteRegistered(address _route) external view returns (bool);
    function isRouteRegistered(bytes32 _routeKey) external view returns (bool);
    function referralCode() external view returns (bytes32);
    function routes() external view returns (address[] memory);

    // keys
 
    function routeKey(address _route) external view returns (bytes32);
    function routeKey(address _trader, bytes32 _routeTypeKey) external view returns (bytes32);

    // deployed contracts

    function orchestrator() external view returns (address);
    function scoreGauge() external view returns (address);

    // puppets

    function puppetSubscriptionExpiry(address _puppet, bytes32 _routeKey) external view returns (uint256);
    function subscribedPuppets(bytes32 _routeKey) external view returns (address[] memory);

    // Route data

    function collateralToken(address _route) external view returns (address);
    function indexToken(address _route) external view returns (address);
    function trader(address _route) external view returns (address);
    function routeAddress(bytes32 _routeKey) external view returns (address);
    function routeAddress(address _trader, address _collateralToken, address _indexToken, bool _isLong, bytes memory _data) external view returns (address);
    function isLong(address _route) external view returns (bool);
    function isPositionOpen(bytes32 _routeKey) external view returns (bool);
    function routeType(address _route) external view returns (bytes32);
}
