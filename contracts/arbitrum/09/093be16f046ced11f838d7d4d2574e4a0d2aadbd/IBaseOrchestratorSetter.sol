// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ================= BaseOrchestratorSetter =====================
// ==============================================================

// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

/// @title IBaseOrchestratorSetter
/// @dev Interface for BaseOrchestratorSetter contract
interface IBaseOrchestratorSetter {

    function setOwner(address _owner) external;
    function setInitializeData(address _keeper, address _platformFeesRecipient, address _routeFactory, address _gauge, address _orchestrator, address _routeSetter) external;
    function setNewAccount(address _route, address _trader, address _collateralToken, address _indexToken, bool _isLong, bytes32 _routeKey, bytes32 _routeTypeKey) external;
    function setRouteType(bytes32 _routeTypeKey, address _collateralToken, address _indexToken, bool _isLong) external;
    function updateSubscription(uint256 _expiry, uint256 _allowance, address _puppet, bool _subscribe, bytes32 _routeKey) external;
    function updateThrottleLimit(uint256 _throttleLimit, address _puppet, bytes32 _routeType) external;
    function updateLastPositionOpenedTimestamp(address _puppet, bytes32 _routeType) external;
    function updatePlatformAccountBalance(uint256 _balance, address _asset) external;
    function updateFees(uint256 _managementFee, uint256 _withdrawalFee, uint256 _performanceFee) external;
    function updateRouteFactory(address _routeFactory) external;
    function updateMultiSubscriber(address _multiSubscriber) external;
    function updateKeeper(address _keeper) external;
    function updateScoreGauge(address _gauge) external;
    function updateReferralCode(bytes32 _referralCode) external;
    function updatePlatformFeesRecipient(address _recipient) external;
    function updatePauseSwitch(bool _paused) external;
    function removeRouteSubscription(address _puppet, bytes32 _routeKey) external;
    function debitPuppetAccount(uint256 _amount, uint256 _feeAmount, address _asset, address _puppet) external;
    function creditPuppetAccount(uint256 _amount, address _asset, address _puppet) external;

    // ============================================================================================
    // Errors
    // ============================================================================================

    error InvalidAllowancePercentage();
    error InvalidSubscriptionExpiry();
    error ZeroAddress();
    error Unauthorized();
}
