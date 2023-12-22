// SPDX-License-Identifier: GPL-3.0

/// This contract deals with the customer exercise logic.

pragma solidity ^0.8.0;

import "./DataTypes.sol";
import "./IProductPool.sol";
import "./ICustomerPool.sol";

contract Execution {
    /**
     * notice Exercise incentive calculation.
     * @param productPoolAddress ProductPool contract address.
     * @param customerId Customer id.
     * @param customerAddress Customer's wallet address.
     * @param productId product id.
     * @param pool CustomerPool contract address.
     */
    function executeWithRewards(
        address productPoolAddress,
        uint256 customerId,
        address customerAddress,
        uint256 productId,
        ICustomerPool pool,
        address stableC
    ) external view returns (DataTypes.CustomerByCrypto memory, DataTypes.CustomerByCrypto memory) {
        IProductPool productPool = IProductPool(productPoolAddress);
        DataTypes.ProductInfo memory product = productPool.getProductInfoByPid(productId);
        DataTypes.PurchaseProduct memory purchaseProduct = pool.getSpecifiedProduct(productId, customerId);
        _validatePurchaseProduct(purchaseProduct, customerAddress);
        DataTypes.CustomerByCrypto memory principal;
        DataTypes.CustomerByCrypto memory rewards;
        if (DataTypes.ProgressStatus.UNREACHED == product.resultByCondition) {
            principal = DataTypes.CustomerByCrypto(
                customerAddress,
                purchaseProduct.tokenAddress,
                purchaseProduct.amount
            );
        } else if (DataTypes.ProgressStatus.REACHED == product.resultByCondition) {
            if (DataTypes.ProductType.BUY_LOW == product.productType) {
                principal = DataTypes.CustomerByCrypto(
                    customerAddress,
                    product.cryptoType,
                    purchaseProduct.cryptoQuantity
                );
            } else {
                principal = DataTypes.CustomerByCrypto(customerAddress, stableC, purchaseProduct.cryptoQuantity);
            }
        }
        rewards = DataTypes.CustomerByCrypto(customerAddress, stableC, purchaseProduct.customerReward);
        return (principal, rewards);
    }

    /// @dev Check product status.
    function _validatePurchaseProduct(
        DataTypes.PurchaseProduct memory customerProduct,
        address customerAddress
    ) private pure returns (bool) {
        require(
            customerProduct.customerAddress == customerAddress,
            "CustomerManager: The user has not purchased the product"
        );
        require(
            customerProduct.amount > 0 && customerProduct.releaseHeight > 0,
            "CustomerManager: The user has not purchased the product"
        );
        return true;
    }
}

