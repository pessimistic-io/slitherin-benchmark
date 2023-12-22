// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IVault.sol";
import "./IFlashLoanRecipient.sol";
import "./Ownable.sol";

interface IOnlyUp {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function sell(uint256 tokenAmount) external returns (uint256);
    function calculatePrice() external view returns (uint256);
    function mintWithBacking(uint256 numTokens, address recipient) external returns (uint256);
}

interface IArbScanRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);   
    function getAmountsOut(uint amountIn, address[] memory path)
        external returns (uint[] memory amounts);    
}


contract mmpr is IFlashLoanRecipient, Ownable {
    address private constant usdc  = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address private constant vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address private constant upplus = 0xcF3f5918880BbdBEF7d9af8f5C845410bDe25316;
    address private constant router = 0x7238FB45146BD8FcB2c463Dc119A53494be57Aac;
    uint256 private slippage = 9950;
    uint256 private slippage_denom = 10000;

    function print (uint256 amount) external onlyOwner {
        IERC20[] memory tokens_to_transfer = new IERC20[](1);
        tokens_to_transfer[0] = IERC20(usdc);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = uint256(amount);
        IVault(vault).flashLoan(this, tokens_to_transfer, amounts, "0x");
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == vault);
        IERC20 usdcReceived = tokens[0];
        uint256 amount = amounts[0];
        uint256 feeAmount = feeAmounts[0];

        //mint UP+ with USDC
        //First approve USDC, then mint 
        IERC20(usdc).approve(address(upplus),amount);
        uint256 amountMinted = IOnlyUp(upplus).mintWithBacking(amount,address(this));

        //swap UP+ for USDC
        address[] memory path = new address[](2);
        path[0] = upplus;
        path[1] = usdc;
        uint256[] memory swapamounts = IArbScanRouter(router).getAmountsOut(amount,path);
        IArbScanRouter(router).swapExactTokensForTokens(amountMinted,(swapamounts[1] * slippage) / slippage_denom,path,address(this),block.timestamp);

        //Repay loan
        usdcReceived.transfer(vault, amount);

        //Send leftover USDC to owner
        usdcReceived.transfer(owner(),usdcReceived.balanceOf(address(this)));

    }        
}
