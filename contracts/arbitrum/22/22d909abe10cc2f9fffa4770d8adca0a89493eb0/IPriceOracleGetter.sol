// Based on aave-protocol implementation
// https://github.com/aave/aave-protocol/blob/e8d020e97/contracts/interfaces/IPriceOracleGetter.sol
// Changes:
// - Upgrade to solidity 0.8.5

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.9;

/************
@title IPriceOracleGetter interface
@notice Interface for the price oracle.*/
interface IPriceOracleGetter {
    /***********
    @dev returns the asset price in ETH
     */
    function getAssetPrice(address _asset) external view returns (uint256);

    /***********
    @dev returns the reciprocal of asset price
     */
    function getAssetPriceReciprocal(address _asset) external view returns (uint256);
}
