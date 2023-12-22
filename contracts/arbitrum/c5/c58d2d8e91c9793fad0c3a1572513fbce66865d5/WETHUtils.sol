//SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.18;

import "./Ownable2StepUpgradeable.sol";
import "./UniswapV2Interface.sol";
import "./StakingConstants.sol";

contract WETHUtils is StakingConstants, Ownable2StepUpgradeable {
    //NOTE:Only involves swapping tokens for tokens, any operations involving ETH will be wrap/unwrap calls to WETH contract

    function wrapEther(uint256 amount) public returns (uint256) {
        (bool sent, ) = address(WETH).call{value: amount}("");
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
        (bool sent, ) = msg.sender.call{value: balance}("");
        require(sent, "Failed to send Ether");
    }
}

