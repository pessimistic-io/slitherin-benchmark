// SPDX-License-Identifier: GPL-3.0

/// This contract deals with product retire judgment processing.

pragma solidity ^0.8.0;

import "./IPriceFeed.sol";
import "./DataTypes.sol";
import "./IProductPool.sol";

contract JudgementCondition {
    /**
     * notice Judge the product retire result.
     * @param productPoolAddress ProductPool contract address.
     * @param productId product id.
     */
    function judgementConditionAmount(
        address productPoolAddress,
        uint256 productId
    ) external view returns (DataTypes.ProgressStatus) {
        IProductPool productPool = IProductPool(productPoolAddress);
        DataTypes.ProductInfo memory product = productPool.getProductInfoByPid(productId);
        require(
            DataTypes.ProgressStatus.UNDELIVERED == product.resultByCondition,
            "ProductManager: non-repeatable delivery"
        );
        require(block.number >= product.releaseHeight, "ProductManager: release height error");
        return _getResultByCondition(product.cryptoExchangeAddress, product.conditionAmount, product.productType);
    }

    /// @dev The seer gets the coin price.
    function getTokenPrice(address token) external view returns (uint256) {
        IPriceFeed priceFeed = IPriceFeed(token);
        int256 price = priceFeed.latestAnswer();
        require(price > 0, "TokenManager: invalid price");
        return uint256(price);
    }

    function _getResultByCondition(
        address cryptoExchangeAddress,
        uint256 conditionAmount,
        DataTypes.ProductType productType
    ) private view returns (DataTypes.ProgressStatus) {
        uint256 currentValue = this.getTokenPrice(cryptoExchangeAddress);
        if (DataTypes.ProductType.BUY_LOW == productType && currentValue >= conditionAmount) {
            return DataTypes.ProgressStatus.UNREACHED;
        } else if (DataTypes.ProductType.BUY_LOW == productType && currentValue < conditionAmount) {
            return DataTypes.ProgressStatus.REACHED;
        } else if (DataTypes.ProductType.SELL_HIGH == productType && currentValue > conditionAmount) {
            return DataTypes.ProgressStatus.REACHED;
        } else {
            return DataTypes.ProgressStatus.UNREACHED;
        }
    }
}

