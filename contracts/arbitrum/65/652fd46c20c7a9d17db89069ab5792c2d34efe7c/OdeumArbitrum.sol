// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import "./ISwapRouter.sol";
import "./OdeumCore.sol";

/// @title A custom ERC20 token
contract Odeum is OdeumCore {
    /// @notice Uniswap V3 pool(Odeum/withdrawTaxToken) fee through
    /// which the exchange of odeum tokens will be carried out when withdrawing the fee
    uint24 public taxWithdrawPoolFee;

    event TaxWithdrawPoolFeeSet(uint24 poolFee);

    /// @notice Function to set taxWithdrawPoolFee
    /// @param poolFee_ The uniswap V3 pool(Odeum/withdrawTaxToken) fee
    function setTaxWithdrawPoolFee(uint24 poolFee_) external onlyOwner {
        require(poolFee_ != 0, "Odeum: poolFee must not be null");
        taxWithdrawPoolFee = poolFee_;

        emit TaxWithdrawPoolFeeSet(poolFee_);
    }

    function withdrawFee() public override onlyOwner {
        if (taxWithdrawToken != address(this)) {
            require(taxWithdrawPoolFee != 0, "Odeum: taxWithdrawPoolFee not set");
        }
        
        super.withdrawFee();
    }

    function _swap(address receiver, uint256 amountIn) internal override returns(uint256 amountOut) {
        ISwapRouter router = ISwapRouter(dexRouter);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(this),
                tokenOut: taxWithdrawToken,
                fee: taxWithdrawPoolFee,
                recipient: receiver,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
        });

        amountOut = router.exactInputSingle(params);
    }
}

