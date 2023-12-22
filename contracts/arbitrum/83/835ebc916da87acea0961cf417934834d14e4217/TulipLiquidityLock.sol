// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IERC20.sol";
import "./Ownable.sol";
import "./IUniswapV2Router02.sol";
import "./IWETH.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";

contract TulipLiquidityLock is Ownable {
    IUniswapV2Router02 public uniswapRouter = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IUniswapV2Factory public uniswapFactory = IUniswapV2Factory(0xc35DADB65012eC5796536bD9864eD8773aBc74C4);
    IWETH public WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    uint256 public releasetimestamp;

    constructor(){
         releasetimestamp = block.timestamp + 180*24*60*60;
    }

    receive() payable external {}

    function remoceLiquidityETHCaller(address token, uint256 liquidity) public payable onlyOwner {
        require(block.timestamp > releasetimestamp, "The opening time is not reached");
        address pair = uniswapFactory.getPair(token, address(WETH));
        IUniswapV2Pair(pair).approve(address(uniswapRouter), liquidity);
        IUniswapV2Router02(uniswapRouter).removeLiquidityETHSupportingFeeOnTransferTokens(
            token,
            liquidity,
            0,
            0,
            msg.sender,
            block.timestamp
        );
    }

    function getLiquidityByToken(address token, uint256 amount) public payable onlyOwner {
        require(block.timestamp > releasetimestamp, "The opening time is not reached");
        IERC20(token).transfer(msg.sender, amount);
    }
}
