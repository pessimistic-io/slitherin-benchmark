//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./console.sol";

import "./libraries_TransferHelper.sol";
import "./interfaces_ISwapRouter.sol";
import "./Ownable.sol";

import "./libraries_TransferHelper.sol";
import "./interfaces_ISwapRouter.sol";

contract UniPancake is Ownable {
    address constant UNISWAP_ROUTER_ADDRESS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant PANCAKESWAP_ROUTER_ADDRESS = 0x32226588378236Fd0c7c4053999F88aC0e5cAc77;

    ISwapRouter private uniswapRouter;
    PancakeSwapInterfaces.ISwapRouter private pancakeswapRouter;

    event SwapExecuted(address indexed _base, address indexed _counter, uint256 _amount);

    constructor () {
        uniswapRouter = ISwapRouter(UNISWAP_ROUTER_ADDRESS);
        pancakeswapRouter = PancakeSwapInterfaces.ISwapRouter(PANCAKESWAP_ROUTER_ADDRESS);
    }

    function u2p(address _base, address _counter, uint _threshold, uint24 _fee) external {
        // get balance
        uint balance = IERC20(_counter).balanceOf(address(this));

        // threshold validation
        require(_threshold >= 0, "no execution: threshold have to be greater than 0");
        require(_threshold < 100, "no execution: threshold have to be smaller than 100");

        // buy from uniswap
        TransferHelper.safeApprove(_counter, address(UNISWAP_ROUTER_ADDRESS), balance);

        ISwapRouter.ExactInputSingleParams memory paramsToBuy = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _counter,
                tokenOut: _base,
                fee: _fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: balance,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        uint256 baseTokenAmount = uniswapRouter.exactInputSingle(paramsToBuy);

        emit SwapExecuted(_base, _counter, baseTokenAmount); 

        // sell from pancakeswap
        PancakeLib.TransferHelper.safeApprove(_base, address(PANCAKESWAP_ROUTER_ADDRESS), baseTokenAmount);
        
        PancakeSwapInterfaces.ISwapRouter.ExactInputSingleParams memory paramsToSell = PancakeSwapInterfaces.ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _base,
                tokenOut: _counter,
                fee: _fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: baseTokenAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        uint256 latestAmountWeHave = pancakeswapRouter.exactInputSingle(paramsToSell);

        emit SwapExecuted(_counter, _base, latestAmountWeHave);

        //last checks
        require(latestAmountWeHave > (balance + (balance / 100 * _threshold)), "rollback: arbitrage rate not enough");
    }

    function p2u(address _base, address _counter, uint _threshold, uint24 _fee) external {
        // get balance
        uint balance = IERC20(_counter).balanceOf(address(this));

        // threshold validation
        require(_threshold >= 0, "no execution: threshold have to be greater than 0");
        require(_threshold < 100, "no execution: threshold have to be smaller than 100");

        // buy from pancakeswap
        PancakeLib.TransferHelper.safeApprove(_counter, address(PANCAKESWAP_ROUTER_ADDRESS), balance);
        
        PancakeSwapInterfaces.ISwapRouter.ExactInputSingleParams memory paramsToBuy = PancakeSwapInterfaces.ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _counter,
                tokenOut: _base,
                fee: _fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: balance,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        uint256 baseAmountWeHave = pancakeswapRouter.exactInputSingle(paramsToBuy);

        emit SwapExecuted(_base, _counter, baseAmountWeHave);

        // sell from uniswap
        TransferHelper.safeApprove(_base, address(UNISWAP_ROUTER_ADDRESS), baseAmountWeHave);

        ISwapRouter.ExactInputSingleParams memory paramsToSell = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _base,
                tokenOut: _counter,
                fee: _fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: baseAmountWeHave,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        uint256 latestAmountWeHave = uniswapRouter.exactInputSingle(paramsToSell);

        emit SwapExecuted(_base, _counter, latestAmountWeHave);

        //last checks
        require(latestAmountWeHave > (balance + (balance / 100 * _threshold)), "rollback: arbitrage rate not enough");
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
