// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Authority} from "./Auth.sol";

interface IRouteFactory {

    // ============================================================================================
    // External Functions
    // ============================================================================================

    /// @notice The ```createRoute``` is called on Orchestrator.registerRoute
    /// @param _orchestrator The address of the Orchestrator
    /// @param _trader The address of the Trader
    /// @param _collateralToken The address of the Collateral Token
    /// @param _indexToken The address of the Index Token
    /// @param _isLong The boolean value of the position
    /// @return _route The address of the new Route
    function createRoute(address _orchestrator, address _trader, address _collateralToken, address _indexToken, bool _isLong) external returns (address _route);

    // ============================================================================================
    // Events
    // ============================================================================================

    event RouteCreated(address indexed caller, address indexed route, address indexed orchestrator, address trader, address collateralToken, address indexToken, bool isLong);
}
