// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ======================== Orchestrator ========================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

import {SafeCast} from "./SafeCast.sol";

import {IPriceFeed} from "./IPriceFeed.sol";
import {IGMXDataStore} from "./IGMXDataStore.sol";

import {IGMXV2OrchestratorReader} from "./IGMXV2OrchestratorReader.sol";
import {IGMXV2OrchestratorSetter} from "./IGMXV2OrchestratorSetter.sol";

import {BaseOrchestrator, Authority} from "./BaseOrchestrator.sol";

/// @title Orchestrator
/// @notice This contract extends the ```BaseOrchestrator``` and is modified to fit GMX V2 (GMX Synthtics)
contract Orchestrator is BaseOrchestrator {

    using SafeCast for int256;

    uint256 private constant _FLOAT_DECIMALS = 30;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    /// @notice The ```constructor``` function is called on deployment
    /// @param _authority The Authority contract instance
    /// @param _reader The Reader contract address
    /// @param _setter The Setter contract address
    constructor(
        Authority _authority,
        address _reader,
        address _setter
    ) BaseOrchestrator(_authority, _reader, _setter) {}

    // ============================================================================================
    // View Functions
    // ============================================================================================

    function getPrice(address _token) override external view returns (uint256) {
        bytes32 _priceFeedKey = keccak256(abi.encode(keccak256(abi.encode("PRICE_FEED")), _token));
        address _priceFeedAddress = IGMXDataStore(IGMXV2OrchestratorReader(address(reader)).gmxDataStore()).getAddress(_priceFeedKey);
        if (_priceFeedAddress == address(0)) revert PriceFeedNotSet();

        IPriceFeed _priceFeed = IPriceFeed(_priceFeedAddress);

        (
            /* uint80 roundID */,
            int256 _price,
            /* uint256 startedAt */,
            uint256 _timestamp,
            /* uint80 answeredInRound */
        ) = _priceFeed.latestRoundData();

        if (_price <= 0) revert InvalidPrice();
        if (block.timestamp > _timestamp && block.timestamp - _timestamp > 24 hours) revert StalePrice();

        return _price.toUint256() * 10 ** (_FLOAT_DECIMALS - _priceFeed.decimals());
    }

    // ============================================================================================
    // Internal Functions
    // ============================================================================================

    function _initialize(bytes memory _data) internal override {
        IGMXV2OrchestratorSetter(address(setter)).storeGMXAddresses(_data);
    }

    // ============================================================================================
    // Errors
    // ============================================================================================

    error PriceFeedNotSet();
    error InvalidPrice();
    error StalePrice();
}
