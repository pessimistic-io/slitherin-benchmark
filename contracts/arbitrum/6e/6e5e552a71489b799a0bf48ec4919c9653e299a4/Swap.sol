//SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./IFlashLoanRecipient.sol";
import "./UniswapV2Interface.sol";
import "./AggregatorV3Interface.sol";
import "./LiquidatorConstants.sol";

contract Swap is ILiquidator, LiquidatorConstants, Ownable {
    constructor (address[] memory underlyingTokens) {
        for (uint8 i = 0; i < underlyingTokens.length; i++) {
            IERC20(underlyingTokens[i]).approve(address(SUSHI_ROUTER), type(uint256).max);
            IERC20(underlyingTokens[i]).approve(address(UNI_ROUTER), type(uint256).max);
            IERC20(underlyingTokens[i]).approve(address(FRAX_ROUTER), type(uint256).max);
        }
        WETH.approve(address(SUSHI_ROUTER), type(uint256).max);
        WETH.approve(address(UNI_ROUTER), type(uint256).max);
        WETH.approve(address(FRAX_ROUTER), type(uint256).max);
        WETH.approve(address(GLP), type(uint256).max);
        WETH.approve(address(this), type(uint256).max);
        GLP.approve(address(GLP_ROUTER), type(uint256).max);
        PLVGLP.approve(address(PLUTUS_DEPOSITOR), type(uint256).max);
    }

    function swapThroughUniswap(
        address token0Address,
        address token1Address,
        uint256 amountIn,
        uint256 minAmountOut
    ) public returns (uint256) {
        uint24 poolFee = 3000;

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(token0Address, poolFee, token1Address),
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });

        uint256 amountOut = UNI_ROUTER.exactInput(params);
        return amountOut;
    }

    //NOTE:Only involves swapping tokens for tokens, any operations involving ETH will be wrap/unwrap calls to WETH contract
    function swapThroughSushiswap(address token0Address, address token1Address, uint256 amountIn, uint256 minAmountOut) public {
        address[] memory path = new address[](2);
        path[0] = token0Address;
        path[1] = token1Address;
        address to = address(this);
        uint256 deadline = block.timestamp;
        SUSHI_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, minAmountOut, path, to, deadline);
    }

    function swapThroughFraxswap(address token0Address, address token1Address, uint256 amountIn, uint256 minAmountOut) public {
        address[] memory path = new address[](2);
        path[0] = token0Address;
        path[1] = token1Address;
        address to = address(this);
        uint256 deadline = block.timestamp;
        FRAX_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, minAmountOut, path, to, deadline);
    }

    //unwraps a position in plvGLP to native ETH, must be wrapped into WETH prior to repaying flash loan
    function unwindPlutusPosition() public {
        PLUTUS_DEPOSITOR.redeemAll();
        uint256 glpAmount = GLP.balanceOf(address(this));
        //TODO: update with a method to calculate minimum out given 2.5% slippage constraints.
        uint256 minOut = 0;
        GLP_ROUTER.unstakeAndRedeemGlp(address(WETH), glpAmount, minOut, address(this));
    }

    function plutusRedeem() public {
        PLUTUS_DEPOSITOR.redeemAll();
    }

    function glpRedeem() public {
        uint256 balance = GLP.balanceOf(address(this));
        GLP_ROUTER.unstakeAndRedeemGlp(address(WETH), balance, 0, address(this));
    }

    function wrapEther(uint256 amount) public returns (uint256) {
        (bool sent, bytes memory data) = address(WETH).call{value: amount}("");
        require(sent, "Failed to send Ether");
        uint256 wethAmount = WETH.balanceOf(address(this));
        return wethAmount;
    }

    function unwrapEther(uint256 amountIn) public returns (uint256) {
        WETH.withdraw(amountIn);
        uint256 etherAmount = address(this).balance;
        return etherAmount;
    }

    function withdrawWETH() external onlyOwner {
        uint256 amount = WETH.balanceOf(address(this));
        WETH.transferFrom(address(this), msg.sender, amount);
    }

    function withdrawETH() external payable onlyOwner {
        uint256 balance = address(this).balance;
        (bool sent, bytes memory data) = msg.sender.call{value: balance}("");
        require(sent, "Failed to send Ether");
    }

    receive() external payable {}
}
