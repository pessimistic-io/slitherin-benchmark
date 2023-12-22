// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./IERC20.sol";
import "./Ownable.sol";
import "./IUniswapV2Router02.sol";

contract TulipGameFeeRewards is Ownable {

    address public routerAddress = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address public wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public tulipGame;
    address public tulipCoin;

    constructor(address tulipGame_) {
        tulipGame = tulipGame_;
    }

    receive() payable external{}

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "Must from real wallet address");
        _;
    }

    function  swapTokenForFund()  public  payable  callerIsUser {
        uint256 contractTokenBalance = IERC20(tulipCoin).balanceOf(address(this));
        if (contractTokenBalance == 0 ){
            return;
        }
        IERC20(tulipCoin).approve(address(routerAddress), contractTokenBalance);
        address[] memory path = new address[](2);
        path[0] = tulipCoin;
        path[1] = wethAddress;
        IUniswapV2Router02(routerAddress).swapExactTokensForETHSupportingFeeOnTransferTokens(
            contractTokenBalance,
            0,
            path,
            tulipGame,
            block.timestamp
        );
    }

    function SetTulipCoin(address tulipCoin_) external onlyOwner {
        tulipCoin = tulipCoin_;
    }

    function SetTulipGame(address tulipGame_) external onlyOwner {
        tulipGame = tulipGame_;
    }

}
