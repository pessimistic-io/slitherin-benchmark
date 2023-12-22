// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./DataTypes.sol";
import "./ICustomerPool.sol";

interface IRetireOption {
    function closeWithSwapAmt(
        uint256 tokenInAmount,
        uint256 tokenOutAmount,
        DataTypes.ProductInfo memory product,
        address stableC
    ) external view returns (DataTypes.ExchangeTotal memory);
}

