// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IRouter {
    function trading() external view returns (address);

    function safxPool() external view returns (address);

    function oracle() external view returns (address);

    function treasury() external view returns (address);

    function darkOracle() external view returns (address);

    function splitter() external view returns (address);
    
    function pool() external view returns (address);

    function mining() external view returns (address);

    function oracleOracle() external view returns (address);

    function isSupportedCurrency(address currency) external view returns (bool);

    function currencies(uint256 index) external view returns (address);

    function currenciesLength() external view returns (uint256);

    function getDecimals(address currency) external view returns(uint8);

    function getPool(address currency) external view returns (address);

    function getPoolShare(address currency) external view returns(uint256);

    function getSafxShare(address currency) external view returns(uint256);

    function getPoolRewards(address currency) external view returns (address);

    function getSafxRewards(address currency) external view returns (address);
}

