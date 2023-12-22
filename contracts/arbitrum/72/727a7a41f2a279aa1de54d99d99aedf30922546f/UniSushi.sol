//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./console.sol";

import "./TransferHelper.sol";
import "./ISwapRouter.sol";
import "./Ownable.sol";

interface ISushiSwapRouter {
    function swapExactETHForTokens(uint amountOutMin,address[] calldata path,address to,uint deadline) external payable returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
    function swapTokensForExactTokens(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn,uint amountOutMin,address[] calldata path,address to,uint deadline) external returns (uint[] memory amounts);
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}

contract UniSushi is Ownable {
    address constant UNISWAP_ROUTER_ADDRESS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant SUSHISWAP_ROUTER_ADDRESS = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

    ISwapRouter private uniswapRouter;
    ISushiSwapRouter private sushiswapRouter;

    event SwapExecuted(address indexed _base, address indexed _counter, uint256 _amount);

    constructor () {
        uniswapRouter = ISwapRouter(UNISWAP_ROUTER_ADDRESS);
        sushiswapRouter = ISushiSwapRouter(SUSHISWAP_ROUTER_ADDRESS);
    }

    function swap(address _base, address _counter, uint256 _amountToSwap, uint _threshold, uint24 _fee) external {
        // balance validation
        uint balance = IERC20(_counter).balanceOf(address(this));
        require(balance > _amountToSwap, "no execution: insufficent balance");

        // threshold validation
        require(_threshold > 0, "no execution: threshold have to be greater than 0");
        require(_threshold < 100, "no execution: threshold have to be smaller than 100");

        // buy from uniswap
        TransferHelper.safeApprove(_counter, address(UNISWAP_ROUTER_ADDRESS), _amountToSwap);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _counter,
                tokenOut: _base,
                fee: _fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _amountToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        uint256 baseTokenAmount = uniswapRouter.exactInputSingle(params);

        emit SwapExecuted(_base, _counter, baseTokenAmount); 

        // sell from sushiswap
        TransferHelper.safeApprove(_base, address(SUSHISWAP_ROUTER_ADDRESS), baseTokenAmount);
        
        address[] memory pathInSecondLeg = new address[](2);
        pathInSecondLeg[0] = _base;
        pathInSecondLeg[1] = _counter;

        uint256[] memory sushiResponse = sushiswapRouter.swapExactTokensForTokens(baseTokenAmount, 0, pathInSecondLeg, address(this), block.timestamp);
        uint256 latestAmountWeHave = sushiResponse[1];

        emit SwapExecuted(_counter, _base, latestAmountWeHave);

        //last checks
        // require(latestAmountWeHave > (_amountToSwap + (_amountToSwap / 100 * _threshold)), "rollback: arbitrage rate not enough");
    }

    function getBalance(
        address _tokenContractAddress
    ) external view returns (uint256) {
        uint balance = IERC20(_tokenContractAddress).balanceOf(address(this));
        return balance;
    }

    function recoverEth() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function recoverTokens(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    receive() external payable {}
}
