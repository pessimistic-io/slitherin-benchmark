// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (utils/Address.sol)

pragma solidity ^0.8.0;

import "./TransferHelper.sol";
import "./IVault.sol";
import "./DataTypes.sol";
import "./ICustomerPool.sol";
import "./IRetireOption.sol";
import "./ISwap.sol";
import "./ConfigurationParam.sol";
import "./IApplyBuyIntent.sol";
import "./IProductPool.sol";

/// @dev Collection of functions related to the address type
library Auxiliary {
    /// @dev Use a Swap contract to swap coins.
    function swapExchange(
        IProductPool productPool,
        IRetireOption dealData,
        ISwap swap,
        IApplyBuyIntent applyBuyIntent,
        uint256 productId,
        address stableC
    ) internal returns (bool, uint256) {
        DataTypes.ProductInfo memory product = productPool.getProductInfoByPid(productId);
        uint256 tokenInAmount = product.soldTotalAmount;
        bool swapResult;
        uint256 amountResult;
        uint256 amount;
        if (tokenInAmount == 0) {
            return (true, amount);
        } else {
            uint256 tokenOutAmount = applyBuyIntent.dealSoldCryptoQuantity(tokenInAmount, product, stableC);
            DataTypes.ExchangeTotal memory exchangeTotal = dealData.closeWithSwapAmt(
                tokenInAmount,
                tokenOutAmount,
                product,
                stableC
            );
            TransferHelper.safeApprove(exchangeTotal.tokenIn, address(swap), exchangeTotal.tokenInAmount);
            if (stableC == exchangeTotal.tokenIn) {
                (swapResult, amountResult) = swap.swapExactOutputSingle(
                    exchangeTotal.tokenOutAmount,
                    exchangeTotal.tokenInAmount,
                    exchangeTotal.tokenIn,
                    exchangeTotal.tokenOut,
                    address(this)
                );
                amount = exchangeTotal.tokenInAmount - amountResult;
            } else {
                (swapResult, amountResult) = swap.swapExactInputSingle(
                    exchangeTotal.tokenInAmount,
                    exchangeTotal.tokenIn,
                    exchangeTotal.tokenOut,
                    address(this)
                );
                amount = amountResult - exchangeTotal.tokenOutAmount;
            }
            require(swapResult, "UniswapManager: uniswap failed");
            return (swapResult, amount);
        }
    }

    /// @dev Update product status.
    function updateProductStatus(
        IProductPool productPool,
        uint256 productId,
        DataTypes.ProgressStatus result
    ) internal returns (bool) {
        bool updateResultByConditionSuccess = productPool._s_retireProductAndUpdateInfo(productId, result);
        require(updateResultByConditionSuccess, "Failed to update the product status");
        return true;
    }

    /// @dev Clear purchase record.
    function delCustomerFromProductList(
        uint256 productId,
        uint256 customerId,
        ICustomerPool customerPool
    ) internal returns (bool) {
        bool delProductByCustomer = customerPool.deleteSpecifiedProduct(productId, customerId);
        require(delProductByCustomer, "Failed to clear the purchase record. Procedure");
        return true;
    }
}

