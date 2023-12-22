// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ======================= BaseReader ===========================
// ==============================================================

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {IBaseRouteSetter} from "./IBaseRouteSetter.sol";
import {IBaseReader} from "./IBaseReader.sol";
import {IDataStore} from "./IDataStore.sol";

import {BaseReaderHelper, Keys} from "./BaseReaderHelper.sol";

/// @title BaseReader
/// @dev Base contract for reading from DataStore
abstract contract BaseReader is IBaseReader {

    address private immutable _wnt;

    uint256 private constant _PRECISION = 1e18;
    uint256 private constant _BASIS_POINTS_DIVISOR = 10000;

    IDataStore public immutable dataStore;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice The ```constructor``` function is called on deployment
    /// @param _dataStore The DataStore contract address
    /// @param _wntAddr The WNT contract address
    constructor(address _dataStore, address _wntAddr) {
        dataStore = IDataStore(_dataStore);
        _wnt = _wntAddr;
    }

    // ============================================================================================
    // View functions
    // ============================================================================================

    // global

    function precision() public pure returns (uint256) {
        return _PRECISION;
    }

    function withdrawalFeePercentage() public view returns (uint256) {
        return dataStore.getUint(Keys.WITHDRAWAL_FEE);
    }

    function managementFeePercentage() public view returns (uint256) { 
        return dataStore.getUint(Keys.MANAGEMENT_FEE);
    }

    function basisPointsDivisor() public pure returns (uint256) {
        return _BASIS_POINTS_DIVISOR;
    }

    function collateralTokenDecimals(address _token) public view returns (uint256) {
        return dataStore.getUint(Keys.collateralTokenDecimalsKey(_token));
    }

    function platformFeeRecipient() public view returns (address) {
        return dataStore.getAddress(Keys.PLATFORM_FEES_RECIPIENT);
    }

    function wnt() external view returns (address) {
        return _wnt;
    }

    function keeper() external view returns (address) {
        return dataStore.getAddress(Keys.KEEPER);
    }

    function isPaused() external view returns (bool) {
        return dataStore.getBool(Keys.PAUSED);
    }

    function isCollateralToken(address _token) external view returns (bool) {
        return dataStore.getBool(Keys.isCollateralTokenKey(_token));
    }

    function isRouteRegistered(address _route) external view returns (bool) {
        return dataStore.getBool(Keys.isRouteRegisteredKey(routeKey(_route)));
    }

    function isRouteRegistered(bytes32 _routeKey) external view returns (bool) {
        return dataStore.getBool(Keys.isRouteRegisteredKey(_routeKey));
    }

    function referralCode() public view returns (bytes32) {
        return dataStore.getBytes32(Keys.REFERRAL_CODE);
    }

    function routes() external view returns (address[] memory) {
        return dataStore.getAddressArray(Keys.ROUTES);
    }

    // keys
 
    function routeKey(address _route) public view returns (bytes32) {
        return BaseReaderHelper.routeKey(dataStore, trader(_route), routeType(_route));
    }

    function routeKey(address _trader, bytes32 _routeTypeKey) public view returns (bytes32) {
        return BaseReaderHelper.routeKey(dataStore, _trader, _routeTypeKey);
    }

    // deployed contracts

    function orchestrator() public view returns (address) {
        return dataStore.getAddress(Keys.ORCHESTRATOR);
    }

    function scoreGauge() external view returns (address) {
        return dataStore.getAddress(Keys.SCORE_GAUGE);
    }

    // puppets

    function puppetSubscriptionExpiry(address _puppet, bytes32 _routeKey) public view returns (uint256) {
        return BaseReaderHelper.puppetSubscriptionExpiry(dataStore, _puppet, _routeKey);
    }

    function subscribedPuppets(bytes32 _routeKey) public view returns (address[] memory) {
        return BaseReaderHelper.subscribedPuppets(dataStore, _routeKey);
    }

    // Route data

    function collateralToken(address _route) public view returns (address) {
        return dataStore.getAddress(Keys.routeCollateralTokenKey(_route));
    }

    function indexToken(address _route) public view returns (address) {
        return dataStore.getAddress(Keys.routeIndexTokenKey(_route));
    }

    function trader(address _route) public view returns (address) {
        return dataStore.getAddress(Keys.routeTraderKey(_route));
    }

    function routeAddress(bytes32 _routeKey) public view returns (address) {
        return dataStore.getAddress(Keys.routeAddressKey(_routeKey));
    }

    function routeAddress(
        address _trader,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        bytes memory _data
    ) external view returns (address) {
        return routeAddress(routeKey(_trader, Keys.routeTypeKey(_collateralToken, _indexToken, _isLong, _data)));
    }

    function isLong(address _route) public view returns (bool) {
        return dataStore.getBool(Keys.routeIsLongKey(_route));
    }

    function isPositionOpen(bytes32 _routeKey) external view returns (bool) {
        return dataStore.getBool(Keys.isPositionOpenKey(_routeKey));
    }

    function routeType(address _route) public view returns (bytes32) {
        return dataStore.getBytes32(Keys.routeRouteTypeKey(_route));
    }
}
