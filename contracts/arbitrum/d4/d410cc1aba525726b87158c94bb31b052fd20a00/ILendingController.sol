// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import "./IOwnable.sol";
import "./IUnifiedOracleAggregator.sol";

interface ILendingController is IOwnable {
    function oracleAggregator()
        external
        view
        returns (IUnifiedOracleAggregator);

    function liqFeeSystem(address _token) external view returns (uint256);

    function liqFeeCaller(address _token) external view returns (uint256);

    function colFactor(address _token) external view returns (uint256);

    function defaultColFactor() external view returns (uint256);

    function depositLimit(
        address _lendingPair,
        address _token
    ) external view returns (uint256);

    function borrowLimit(
        address _lendingPair,
        address _token
    ) external view returns (uint256);

    function tokenPrice(address _token) external view returns (uint256);

    function minBorrow(address _token) external view returns (uint256);

    function tokenPrices(
        address _tokenA,
        address _tokenB
    ) external view returns (uint256, uint256);

    function tokenSupported(address _token) external view returns (bool);

    function hasChainlinkOracle(address _token) external view returns (bool);

    function isBaseAsset(address _token) external view returns (bool);

    function minObservationCardinalityNext() external view returns (uint16);

    function preparePool(address _tokenA, address _tokenB) external;
}

