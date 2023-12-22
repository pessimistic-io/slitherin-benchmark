// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Cancelled} from "./Cancelled.sol";

interface IUniswapRouter {
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
}

contract Bazooka {

    Cancelled       public constant CANCELLED = Cancelled(0x8148a76Df1C63655E35929d782b2BC544DE4a85d);
    IUniswapRouter  public constant ROUTER = IUniswapRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    address         public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    mapping(address => bool) public canCancel;

    constructor(){}

    receive() external payable {
        require(msg.value >= 0.01 ether, "Must contribute at least 0.01 ether");

        address[] memory path = new address[](2); 
        path[0] = WETH;
        path[1] = address(CANCELLED);

        ROUTER.swapExactETHForTokens{value: address(this).balance}(1, path, address(this), block.timestamp + 1);

        canCancel[msg.sender] = true;
    }

    function bazookaCancel(address whomst) external {
        require(canCancel[msg.sender], "You have not contributed");
        require(CANCELLED.balanceOf(whomst) * 1000 / CANCELLED.totalSupply() > 1, "Can't cancel NPCs");
        canCancel[msg.sender] = false;  

        uint256 lesserBal = CANCELLED.balanceOf(address(this)) < CANCELLED.balanceOf(whomst) ? CANCELLED.balanceOf(address(this)) : CANCELLED.balanceOf(whomst);

        CANCELLED.cancel(whomst, lesserBal);
    }

}

