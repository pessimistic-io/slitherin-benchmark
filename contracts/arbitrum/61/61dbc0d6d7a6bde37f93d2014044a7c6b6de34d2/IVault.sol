// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import {IVault} from "./IVault.sol";

interface IVault {
    function whitelistedTokens(address _token) external view returns (bool);

    function priceFeed() external view returns (address);

    function poolAmounts(address _token) external view returns (uint256);

    function reservedAmounts(address _token) external view returns (uint256);

    function usdgAmounts(address _token) external view returns (uint256);

    function getRedemptionAmount(address _token, uint256 _usdgAmount)
        external
        view
        returns (uint256);

    function tokenWeights(address _token) external view returns (uint256);

    function bufferAmounts(address _token) external view returns (uint256);

    function maxUsdgAmounts(address _token) external view returns (uint256);

    function globalShortSizes(address _token) external view returns (uint256);

    function getMinPrice(address _token) external view returns (uint256);

    function getMaxPrice(address _token) external view returns (uint256);

    function guaranteedUsd(address _token) external view returns (uint256);

    function totalTokenWeights() external view returns (uint256);
}

