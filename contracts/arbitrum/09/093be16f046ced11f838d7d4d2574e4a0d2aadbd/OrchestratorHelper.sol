// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Keys} from "./Keys.sol";

import {IBaseOrchestratorReader} from "./IBaseOrchestratorReader.sol";
import {IBaseOrchestratorSetter} from "./IBaseOrchestratorSetter.sol";

import {IBaseRouteFactory} from "./IBaseRouteFactory.sol";

library OrchestratorHelper {

    // ============================================================================================
    // View Functions
    // ============================================================================================

    function isRouteRegistered(IBaseOrchestratorReader _reader, address _route) external view {
        if (!_reader.isRouteRegistered(_route)) revert NotRoute();
    }

    function isPaused(IBaseOrchestratorReader _reader) external view {
        if (_reader.isPaused()) revert Paused();
    }

    function validateRouteKey(IBaseOrchestratorReader _reader, bytes32 _routeKey) public view returns (address _route) {
        _route = _reader.routeAddress(_routeKey);
        if (_route == address(0)) revert RouteNotRegistered();
    }

    function validatePuppetInput(
        IBaseOrchestratorReader _reader,
        uint256 _amount,
        address _puppet,
        address _asset
    ) external view {
        if (_amount == 0) revert ZeroAmount();
        if (_puppet == address(0)) revert ZeroAddress();
        if (_asset == address(0)) revert ZeroAddress();
        if (!_reader.isCollateralToken(_asset)) revert NotCollateralToken();
    }

    // ============================================================================================
    // Mutated Function
    // ============================================================================================

    function registerRouteAccount(
        IBaseOrchestratorReader _reader,
        IBaseOrchestratorSetter _setter,
        address _trader,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        bytes memory _data
    ) external returns (address _route, bytes32 _routeKey, bytes32 _routeTypeKey) {
        if (_collateralToken == address(0) || _indexToken == address(0)) revert ZeroAddress();

        _routeTypeKey = Keys.routeTypeKey(_collateralToken, _indexToken, _isLong, _data);
        if (!_reader.isRouteTypeRegistered(_routeTypeKey)) revert RouteTypeNotRegistered();

        _routeKey = _reader.routeKey(_trader, _routeTypeKey);
        if (_reader.isRouteRegistered(_routeKey)) revert RouteAlreadyRegistered();

        _route = IBaseRouteFactory(_reader.routeFactory()).registerRouteAccount(
            _reader.routeReader(),
            _reader.routeSetter(),
            _data
        );

        _setter.setNewAccount(
            _route,
            _trader,
            _collateralToken,
            _indexToken,
            _isLong,
            _routeKey,
            _routeTypeKey
        );
    }

    function removeExpiredSubscriptions(
        IBaseOrchestratorReader _reader,
        IBaseOrchestratorSetter _setter,
        bytes32 _routeKey
    ) external {
        uint256 i = 0;
        while (i < _reader.subscribedPuppetsCount(_routeKey)) {
            address _puppet = _reader.puppetAt(_routeKey, i);
            if (_reader.puppetSubscriptionExpiry(_puppet, _routeKey) <= block.timestamp) {
                _setter.removeRouteSubscription(_puppet, _routeKey);
            } else {
                i++;
            }
        }
    }

    function subscribePuppet(
        IBaseOrchestratorReader _reader,
        IBaseOrchestratorSetter _setter,
        uint256 _expiry,
        uint256 _allowance,
        address _trader,
        address _puppet,
        bytes32 _routeTypeKey,
        bool _subscribe
    ) external returns (address _route) {
        bytes32 _routeKey = _reader.routeKey(_trader, _routeTypeKey);
        _route = validateRouteKey(_reader, _routeKey);
        if (_reader.isWaitingForCallback(_routeKey)) revert RouteWaitingForCallback();

        _setter.updateSubscription(_expiry, _allowance, _puppet, _subscribe, _routeKey);
    }

    function updateLastPositionOpenedTimestamp(
        IBaseOrchestratorReader _reader,
        IBaseOrchestratorSetter _setter,
        address _route,
        address[] memory _puppets
    ) external returns (bytes32 _routeType) {
        _routeType = _reader.routeType(_route);
        for (uint256 i = 0; i < _puppets.length; i++) {
            _setter.updateLastPositionOpenedTimestamp(_puppets[i], _routeType);
        }
    }

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NotRoute();
    error Paused();
    error ZeroAddress();
    error ZeroAmount();
    error RouteTypeNotRegistered();
    error RouteAlreadyRegistered();
    error RouteNotRegistered();
    error RouteWaitingForCallback();
    error NotCollateralToken();
}
