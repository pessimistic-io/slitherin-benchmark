//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./console.sol";

import "./Ownable.sol";

interface IUniswapV2Router {
    function swapExactTokensForETH(uint amountIn,uint amountOutMin,address[] calldata path,address to,uint deadline) external returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut,address[] calldata path,address to,uint deadline) external payable returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin,address[] calldata path,address to,uint deadline) external payable returns (uint[] memory amounts);
}

interface ISushiSwapRouter {
    function swapExactETHForTokens(uint amountOutMin,address[] calldata path,address to,uint deadline) external payable returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
    function swapTokensForExactTokens(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn,uint amountOutMin,address[] calldata path,address to,uint deadline) external returns (uint[] memory amounts);
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
}

interface IERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
    function allowance(address owner,address spender) external view returns (uint);
    function approve(address spender, uint amount) external returns (bool);
    function transferFrom(address sender,address recipient,uint amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}

contract UniSushi is Ownable {
    address constant UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant SUSHISWAP_ROUTER_ADDRESS = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

    IUniswapV2Router private uniswapRouter;
    ISushiSwapRouter private sushiswapRouter;

    constructor() {
        uniswapRouter = IUniswapV2Router(UNISWAP_ROUTER_ADDRESS);
        sushiswapRouter = ISushiSwapRouter(SUSHISWAP_ROUTER_ADDRESS);
    }

    function swap(address _base, address _counter, uint256 _amountToSwap, uint _threshold) external {
        // balance validation
        uint balance = IERC20(_counter).balanceOf(address(this));
        require(balance > _amountToSwap, "no execution: insufficent balance");

        // threshold validation
        require(_threshold > 0, "no execution: threshold have to be greater than 0");
        require(_threshold < 100, "no execution: threshold have to be smaller than 100");

        // prepare paths
        address[] memory pathInFirstLeg = new address[](2);
        pathInFirstLeg[0] = _base;
        pathInFirstLeg[1] = _counter;

        address[] memory pathInSecondLeg = new address[](2);
        pathInSecondLeg[0] = _counter;
        pathInSecondLeg[1] = _base;

        // what if we buy base token from uniswap
        uint256[] memory uniSimulationResponse = uniswapRouter.getAmountsOut(_amountToSwap, pathInFirstLeg);
        uint256 baseCurrencyAmount = uniSimulationResponse[1];

        // what if we sell base token in sushiswap
        uint256[] memory sushiSimulationResponse = sushiswapRouter.getAmountsOut(baseCurrencyAmount, pathInSecondLeg);
        uint256 counterCurrencyAmount = sushiSimulationResponse[1];

        // check rates before swap
        require(counterCurrencyAmount > (_amountToSwap + (_amountToSwap / 100 * _threshold)), "no execution: arbitrage rate not enough");

        // buy from uniswap
        IERC20(_counter).approve(address(UNISWAP_ROUTER_ADDRESS), _amountToSwap); 
        uint256[] memory uniswapResponse = uniswapRouter.swapExactTokensForTokens(_amountToSwap, 0, pathInFirstLeg, address(this), block.timestamp);
        uint256 baseTokenAmount = uniswapResponse[1];

        // sell from sushiswap
        IERC20(_base).approve(address(SUSHISWAP_ROUTER_ADDRESS), baseTokenAmount); 
        uint256[] memory sushiResponse = sushiswapRouter.swapExactTokensForTokens(baseTokenAmount, 0, pathInSecondLeg, address(this), block.timestamp);
        uint256 latestAmountWeHave = sushiResponse[1];

        //last checks
        require(latestAmountWeHave > (_amountToSwap + (_amountToSwap / 100 * _threshold)), "rollback: arbitrage rate not enough");
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
