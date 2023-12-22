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

    function getAmountIn(bytes memory path, uint256 amountOut) public override returns (uint256 amountIn) {
        // try quoter.quoteExactOutput(path, amountOut) {} catch Error(string memory revertData) {
        //     amountIn = abi.decode(bytes(revertData), (uint256));
        // }
    }

    function getAmountIns(bytes memory path, uint256 amountOut) public returns (string memory amountIn) {
        try quoter.quoteExactOutput(path, amountOut) {} catch Error(string memory revertData) {
            amountIn = revertData;
        }
    }

    function swap(
        bytes memory path,
        address tokenIn,
        uint256 amountIn,
        address recipient
    ) public override returns (uint256 amountOut) {
        // TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        // TransferHelper.safeApprove(address(tokenIn), address(router), amountIn);
        // ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
        //     path: path,
        //     recipient: address(this),
        //     deadline: block.timestamp,
        //     amountIn: amountIn,
        //     amountOutMinimum: 1
        // });
        // amountOut = router.exactInput(params);
        // weth.withdraw(amountOut);
        // payable(recipient).transfer(amountOut);
        // emit Swapped(recipient, tokenIn, amountIn, amountOut);
    }
}

