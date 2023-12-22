// SPDX-License-Identifier: GPL-3.0

///  This contract deals with the product retire logic.
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./DataTypes.sol";
import "./IProductPool.sol";
import "./ICustomerPool.sol";

contract RetireOption {
    /**
     * notice Currency conversion calculation.
     * @param tokenInAmount Incoming quantity.
     * @param tokenOutAmount Outcoming quantity.
     * @param product Product info.
     */
    function closeWithSwapAmt(
        uint256 tokenInAmount,
        uint256 tokenOutAmount,
        DataTypes.ProductInfo memory product,
        address stableC
    ) external pure returns (DataTypes.ExchangeTotal memory) {
        if (DataTypes.ProductType.BUY_LOW == product.productType) {
            return DataTypes.ExchangeTotal(stableC, product.cryptoType, tokenInAmount, tokenOutAmount);
        } else {
            return DataTypes.ExchangeTotal(product.cryptoType, stableC, tokenInAmount, tokenOutAmount);
        }
    }
}

