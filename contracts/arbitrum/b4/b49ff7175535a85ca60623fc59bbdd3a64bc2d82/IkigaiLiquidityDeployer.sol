// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./IPancakeRouter01.sol";
import "./IERC20.sol";

contract LiquidityDeployer {
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;

    address immutable deployer;

    constructor() {
        deployer = msg.sender;
    }

    function deployLiquidity(address router, address token) public {
        require(msg.sender == deployer, "not deployer");

        IPancakeRouter01 ikiRouter = IPancakeRouter01(router);

        uint256 tokenBalance = IERC20(token).balanceOf(address(this));

        uint256 tokenSplitOne = tokenBalance / 2;

        uint256 tokenSplitTwo = tokenBalance - tokenSplitOne;

        uint256 balanceWETH = IERC20(WETH).balanceOf(address(this));

        ikiRouter.addLiquidity(
            token,
            WETH,
            tokenSplitOne,
            balanceWETH,
            (tokenSplitOne * 75) / 100,
            (balanceWETH * 75) / 100,
            DEAD,
            type(uint256).max
        );

        uint256 balanceUSDT = IERC20(USDT).balanceOf(address(this));

        ikiRouter.addLiquidity(
            token,
            WETH,
            tokenSplitTwo,
            balanceUSDT,
            (tokenSplitOne * 75) / 100,
            (balanceUSDT * 75) / 100,
            DEAD,
            type(uint256).max
        );
    }

    function rescue() public {
        // cant rescue ikigai token because that would defeat the purpose.
        require(msg.sender == deployer, "not deployer");

        IERC20 _usdt = IERC20(USDT);
        IERC20 _weth = IERC20(WETH);

        _usdt.transfer(deployer, _usdt.balanceOf(address(this)));
        _weth.transfer(deployer, _weth.balanceOf(address(this)));
    }
}

