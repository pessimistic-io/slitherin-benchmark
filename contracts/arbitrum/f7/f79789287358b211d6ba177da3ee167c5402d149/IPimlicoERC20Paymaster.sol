// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "./IOracle.sol";

interface IPimlicoERC20Paymaster {
    function priceUpdateThreshold() external view returns (uint32);

    function tokenOracle() external view returns (IOracle);

    function nativeAssetOracle() external view returns (IOracle);

    function tokenDecimals() external view returns (uint256);

    function priceDenominator() external view returns (uint256);

    function previousPrice() external view returns (uint256);

    function updatePrice() external;
}

