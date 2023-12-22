// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./TransferHelper.sol";
import "./ISwapRouter.sol";
import "./IQuoter.sol";
import "./IWETH9.sol";
import "./SwapperConnector.sol";

contract UniswapV3Swapper is SwapperConnector {
    ISwapRouter public immutable router;
    IQuoter public immutable quoter;
    IWETH9 public immutable weth;

    constructor(address router_, address quoter_, address weth_) {
        require(router_ != address(0), "Swapper: Router is zero address");
        require(quoter_ != address(0), "Swapper: Quoter is zero address");
        require(weth_ != address(0), "Swapper: WETH is zero address");
        router = ISwapRouter(router_);
        quoter = IQuoter(quoter_);
        weth = IWETH9(weth_);
    }

    receive() external payable {}

    function getAmountIn(bytes memory path, uint256 amountOut) public override returns (uint256 amountIn) {
        (address tokenIn, uint24 fee, address tokenOut) = abi.decode(path, (address, uint24, address));
        amountIn = quoter.quoteExactOutputSingle(tokenIn, tokenOut, fee, amountOut, 0);
    }

    function swap(
        bytes memory path,
        address tokenIn,
        uint256 amountIn,
        address recipient
    ) public override returns (uint256 amountOut) {
        (address tokenInPath, uint24 fee, address tokenOut) = abi.decode(path, (address, uint24, address));
        require(tokenIn == tokenInPath, "UniswapV3Swapper: TokenIn is invalid");
        require(amountIn > 0, "UniswapV3Swapper: AmountIn is not positive");
        require(recipient != address(0), "UniswapV3Swapper: Recipient is zero address");
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(address(tokenIn), address(router), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });
        amountOut = router.exactInputSingle(params);
        weth.withdraw(amountOut);
        payable(recipient).transfer(amountOut);
        emit Swapped(recipient, tokenIn, amountIn, amountOut);
    }
}

