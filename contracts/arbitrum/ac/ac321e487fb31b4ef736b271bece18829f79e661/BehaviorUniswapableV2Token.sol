// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";
import "./BehaviorSwapableToken.sol";
import "./console.sol";

contract BehaviorUniswapableV2Token is BehaviorSwapableToken {
    IUniswapV2Router02 private contractUniswapV2Router;
    IUniswapV2Pair public contractUniswapV2Pair;
    address public addressUniswapV2Pair;

    constructor(address _addressRouter) {
        contractUniswapV2Router = IUniswapV2Router02(_addressRouter);
    }

    function createAndConfigureEmptyTradeablePairEth() public onlyOwner {
        if (addressUniswapV2Pair == address(0)) {
            IUniswapV2Factory contractUniswapV2Factory = IUniswapV2Factory(contractUniswapV2Router.factory());

            addressUniswapV2Pair = contractUniswapV2Factory.createPair(address(this), contractUniswapV2Router.WETH());

            setTradingContractAddress(addressUniswapV2Pair, true);

            _onTradeablePairCreated(addressUniswapV2Pair);
        }
    }

    function _onTradeablePairCreated(address _addressUniswapV2Pair) internal virtual {}
}

contract BehaviorUniswapableV2 is Ownable {
    IUniswapV2Router02 contractUniswapV2Router;

    address addressManagedToken;

    address addressQuoteToken;

    constructor(address _addressRouter, address _addressManagedToken) {
        contractUniswapV2Router = IUniswapV2Router02(_addressRouter);
        addressManagedToken = _addressManagedToken;
        addressQuoteToken = contractUniswapV2Router.WETH();
    }

    function getCurrentPriceRatio() public view returns (uint112 amount0, uint112 amount1) {
        IUniswapV2Factory factory = IUniswapV2Factory(contractUniswapV2Router.factory());
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(addressManagedToken, addressQuoteToken));
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        if (pair.token0() == addressManagedToken) return (reserve0, reserve1);
        else return (reserve1, reserve0);
    }

    function _swapTokensForEth(uint256 _amount, uint256 _minAmountOut, address _to) internal returns (uint256) {
        IERC20 tokenThis = IERC20(addressManagedToken);
        tokenThis.approve(address(contractUniswapV2Router), _amount);

        address[] memory pathSwap = new address[](2);
        pathSwap[0] = addressManagedToken;
        pathSwap[1] = addressQuoteToken;

        uint256 originalETHBalance = _to.balance;

        contractUniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            _amount,
            _minAmountOut,
            pathSwap,
            _to,
            block.timestamp
        );
        uint256 afterSwapETHBalance = _to.balance;
        uint256 purchasedAmountEth = afterSwapETHBalance - originalETHBalance;

        return purchasedAmountEth;
    }

    function _swapEthForTokens(uint256 _minAmountOut, address _to) internal returns (uint256) {
        IERC20 tokenThis = IERC20(addressManagedToken);

        address[] memory pathSwap = new address[](2);
        pathSwap[0] = addressQuoteToken;
        pathSwap[1] = addressManagedToken;

        uint256 originalTokenBalance = tokenThis.balanceOf(_to);

        contractUniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(
            _minAmountOut,
            pathSwap,
            _to,
            block.timestamp
        );
        uint256 afterSwapTokenBalance = tokenThis.balanceOf(_to);
        uint256 purchasedAmountEth = afterSwapTokenBalance - originalTokenBalance;

        return purchasedAmountEth;
    }

    function _addTokensToLiquidityETH(uint256 _amountToken, uint256 _amountETH) internal {
        IERC20(addressManagedToken).approve(address(contractUniswapV2Router), _amountToken);

        contractUniswapV2Router.addLiquidityETH{value: _amountETH}(
            addressManagedToken,
            _amountToken,
            0,
            0,
            owner(),
            block.timestamp
        );
    }

    function _swapTokensToHalfAndCreateLpETH(uint256 _amount) internal {
        uint256 tokensHalf = _amount / 2;
        uint256 ethForLiquidity = _swapTokensForEth(tokensHalf, 0, address(this));
        _addTokensToLiquidityETH(tokensHalf, ethForLiquidity);
    }

    receive() external payable {}
}

