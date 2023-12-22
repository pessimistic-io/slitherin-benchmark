// SPDX-License-Identifier: UNLICENSED
// © Copyright AutoDCA. All Rights Reserved

pragma solidity 0.8.9;

import "./IERC20.sol";
import "./Ownable2Step.sol";
import "./ISwapRouter.sol";

import "./ICustomSwapRouter.sol";
import "./XDCAManager.sol";

contract USDCToXDCASwapRouter is ICustomSwapRouter, Ownable2Step {
    address public constant DCA = 0x965F298E4ade51C0b0bB24e3369deB6C7D5b3951;
    address public constant XDCA = 0xe950A64C7D2E2495f8D48f9CC47ad833457998AD;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    ISwapRouter public uniswapV3Router;
    XDCAManager public xdcaManager;

    constructor(ISwapRouter uniswapV3Router_, XDCAManager xdcaManager_) {
        uniswapV3Router = uniswapV3Router_;
        xdcaManager = xdcaManager_;
    }

    function exchangeToken(
        uint256 amount,
        uint256 beliefPrice
    ) external returns (uint256) {
        IERC20(USDC).transferFrom(msg.sender, address(this), amount);
        IERC20(USDC).approve(address(uniswapV3Router), amount);
        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: abi.encodePacked(USDC, WETH, DCA),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: (amount * beliefPrice) / 1e6
            });
        uint256 received = uniswapV3Router.exactInput(params);
        IERC20(DCA).approve(address(xdcaManager), received);
        XDCAManager(xdcaManager).lock(received);
        IERC20(XDCA).transfer(msg.sender, received);
        return received;
    }
}

