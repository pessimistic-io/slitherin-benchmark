// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IOracle {
    /**
     * @notice Returns the price of 1 fxAsset in ETH
     * @param fxAsset the asset to get a rate for
     * @return unitPrice the cost of a single fxAsset in ETH
     */
    function getRate(address fxAsset) external view returns (uint256 unitPrice);

    /**
     * @notice A setter function to add or update an oracle for a given fx asset.
     * @param fxAsset the asset to update
     * @param oracle the oracle to set for the fxAsset
     */
    function setOracle(address fxAsset, address oracle) external;
}

