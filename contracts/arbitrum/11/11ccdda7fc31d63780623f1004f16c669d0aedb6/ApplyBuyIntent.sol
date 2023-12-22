// SPDX-License-Identifier: GPL-3.0

/// The contract does the logical processing of customer purchase productst.

pragma solidity ^0.8.0;

import "./ConfigurationParam.sol";
import "./DataTypes.sol";
import "./ConfigurationParam.sol";
import "./IProductPool.sol";
import "./ICustomerPool.sol";

contract ApplyBuyIntent {
    /**
     * notice Customers purchase products.
     * @param amount Purchase quantity.
     * @param _pid Product id.
     * @param productPool ProductPool contract address.
     */
    function dealApplyBuyCryptoQuantity(
        uint256 amount,
        uint256 _pid,
        IProductPool productPool,
        address stableC
    ) external view returns (uint256, address) {
        DataTypes.ProductInfo memory product = productPool.getProductInfoByPid(_pid);
        uint256 cryptoQuantity;
        address etcToken;
        require(amount >= product.customerQuantity, "PurchaseManager: amount is below the minimum value");
        require(amount <= (product.saleTotalAmount - product.soldTotalAmount), "purchase volume is out of bounds");
        require(block.timestamp < product.sellEndTime, "PurchaseManager: exceeding the deadline for sale");
        require(
            DataTypes.ProgressStatus.UNDELIVERED == product.resultByCondition,
            "ProductManager: undelivered product"
        );
        (cryptoQuantity, etcToken) = _calculateCryptoQuantity(product, amount, stableC);
        return (cryptoQuantity, etcToken);
    }

    /**
     * notice Calculate the number of subscriptions.
     * @param amount Purchase amount.
     * @param product product info.
     */
    function dealSoldCryptoQuantity(
        uint256 amount,
        DataTypes.ProductInfo memory product,
        address stableC
    ) external pure returns (uint256) {
        uint256 cryptoQuantity;
        require(amount > 0, "BasePositionManager: amount must be greater than 0");
        (cryptoQuantity, ) = _calculateCryptoQuantity(product, amount, stableC);
        return cryptoQuantity;
    }

    /// @dev Handle subscription quantity calculation.
    function _calculateCryptoQuantity(
        DataTypes.ProductInfo memory product,
        uint256 amount,
        address stableC
    ) internal pure returns (uint256, address) {
        uint256 cryptoQuantity;
        address etcToken;
        if (ConfigurationParam.WBTC == product.cryptoType) {
            (cryptoQuantity, etcToken) = _calculateCryptoQuantityByWBTC(product, amount, stableC);
        } else if (ConfigurationParam.WETH == product.cryptoType) {
            (cryptoQuantity, etcToken) = _calculateCryptoQuantityByWETH(product, amount, stableC);
        }
        require(cryptoQuantity > 0 && etcToken != address(0), "BasePositionManager: product information exception");
        return (cryptoQuantity, etcToken);
    }

    /// @dev Handle WETH subscription quantity calculation.
    function _calculateCryptoQuantityByWETH(
        DataTypes.ProductInfo memory product,
        uint256 amount,
        address stableC
    ) private pure returns (uint256, address) {
        uint256 cryptoQuantity;
        address etcToken;
        if (product.productType == DataTypes.ProductType.BUY_LOW) {
            cryptoQuantity = _calculateBuyLow(amount, product.conditionAmount, ConfigurationParam.WETH_DECIMAL);
            etcToken = stableC;
        } else if (product.productType == DataTypes.ProductType.SELL_HIGH) {
            cryptoQuantity = _calculateSellHigh(amount, product.conditionAmount, ConfigurationParam.WETH_DECIMAL);
            etcToken = product.cryptoType;
        }
        return (cryptoQuantity, etcToken);
    }

    /// @dev Handle WBTC subscription quantity calculation.
    function _calculateCryptoQuantityByWBTC(
        DataTypes.ProductInfo memory product,
        uint256 amount,
        address stableC
    ) private pure returns (uint256, address) {
        uint256 cryptoQuantity;
        address etcToken;
        if (product.productType == DataTypes.ProductType.BUY_LOW) {
            cryptoQuantity = _calculateBuyLow(amount, product.conditionAmount, ConfigurationParam.WBTC_DECIMAL);
            etcToken = stableC;
        } else if (product.productType == DataTypes.ProductType.SELL_HIGH) {
            cryptoQuantity = _calculateSellHigh(amount, product.conditionAmount, ConfigurationParam.WBTC_DECIMAL);
            etcToken = product.cryptoType;
        }
        return (cryptoQuantity, etcToken);
    }

    /// @dev Buy type calculates the quantity available for purchase.
    function _calculateBuyLow(
        uint256 amount,
        uint256 conditionAmount,
        uint256 cryptoTypeDecimal
    ) private pure returns (uint256) {
        uint256 cryptoQuantity = (amount * cryptoTypeDecimal * ConfigurationParam.ORACLE_DECIMAL) /
            (conditionAmount * ConfigurationParam.STABLEC_DECIMAL);
        return cryptoQuantity;
    }

    /// @dev Sell type Calculates the quantity available for sale.
    function _calculateSellHigh(
        uint256 amount,
        uint256 conditionAmount,
        uint256 cryptoTypeDecimal
    ) private pure returns (uint256) {
        uint256 cryptoQuantity = (amount * conditionAmount * ConfigurationParam.STABLEC_DECIMAL) /
            (cryptoTypeDecimal * ConfigurationParam.ORACLE_DECIMAL);
        return cryptoQuantity;
    }
}

