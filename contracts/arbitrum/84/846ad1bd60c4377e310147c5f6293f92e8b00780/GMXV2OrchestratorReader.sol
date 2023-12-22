// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IGMXV2OrchestratorReader} from "./IGMXV2OrchestratorReader.sol";
import {IGMXV2RouteReader} from "./IGMXV2RouteReader.sol";

import {GMXV2Keys} from "./GMXV2Keys.sol";

import {BaseOrchestratorReader} from "./BaseOrchestratorReader.sol";

/// @title GMXV2Reader
/// @dev Extends the BaseOrchestratorReader contract with GMX V2 integration specific logic
contract GMXV2OrchestratorReader is IGMXV2OrchestratorReader, BaseOrchestratorReader {

    IGMXV2RouteReader private immutable _routeReader;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice The ```constructor``` function is called on deployment
    /// @param _dataStore The DataStore contract address
    /// @param _wntAddr The WNT contract address
    /// @param _routeReaderAddr The GMXRouteReader contract address
    constructor(address _dataStore, address _wntAddr, address _routeReaderAddr) BaseOrchestratorReader(_dataStore, _wntAddr) {
        _routeReader = IGMXV2RouteReader(_routeReaderAddr);
    }

    // ============================================================================================
    // View functions
    // ============================================================================================

    function routeReader() override external view returns (address) {
        return address(_routeReader);
    }

    function isWaitingForCallback(bytes32 _routeKey) override external view returns (bool) {
        return _routeReader.isWaitingForCallback(_routeKey);
    }

    function positionKey(address _route) override public view returns (bytes32) {
        return keccak256(
            abi.encode(
                _route,
                dataStore.getAddress(GMXV2Keys.routeMarketToken(_route)),
                collateralToken(_route),
                isLong(_route)
            ));
    }

    function gmxDataStore() external view returns (address) {
        return dataStore.getAddress(GMXV2Keys.GMX_DATA_STORE);
    }
}
