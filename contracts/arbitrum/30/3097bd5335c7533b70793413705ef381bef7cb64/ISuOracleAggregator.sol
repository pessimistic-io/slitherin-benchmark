// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./ISuOracle.sol";

interface ISuOracleAggregator is ISuOracle {
    /* ===================== ERRORS ===================== */
    error NoOracleFound(address asset);
    error NoOracleImplementation();
    error BadOracleId();

    /* ====================== VARS ====================== */
    function assetToOracle (address asset) external view returns ( uint256 );
    function oracleImplementations (uint256 oracleId) external view returns ( ISuOracle );

    /* ==================== METHODS ==================== */
    /**
       * @notice assign address of oracle implementation to the oracleId
    * @param oracleId - number 0,1, etc to assign the oracle
    * @param oracleImplementation - an address with ISuOracle implementation contract
    **/
    function setOracleImplementation(uint256 oracleId, ISuOracle oracleImplementation) external;

    /**
    * @notice specify what oracleId should be used for each assets. Checks that oracleId has an implementation
    **/
    function setOracleIdForAssets(address[] memory assets, uint256 oracleId) external;

    /* ==================== VIEW METHODS ==================== */
    /**
    * @return true if oracle is set to this asset, false otherwise
    **/
    function hasPriceForAsset(address asset) external view returns(bool);
}

