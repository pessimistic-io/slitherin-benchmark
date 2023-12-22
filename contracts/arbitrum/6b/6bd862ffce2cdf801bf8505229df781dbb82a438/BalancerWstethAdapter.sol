// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

// Interfaces
import {IVault} from "./IVault.sol";
import {IAsset} from "./IAsset.sol";
import {IERC20} from "./IERC20.sol";

library BalancerWstethAdapter {
    address public constant weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant wsteth = 0x5979D7b546E38E414F7E9822514be443A4800529;

    bytes32 public constant wethwstethPool = hex"36bf227d6bac96e2ab1ebb5492ecec69c691943f000200000000000000000316";

    function swapWethToWstEth(
        IVault self,
        address fromAddress,
        address toAddress,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) public returns (uint256) {
        IVault.SingleSwap memory singleSwap =
            IVault.SingleSwap(wethwstethPool, IVault.SwapKind.GIVEN_IN, IAsset(weth), IAsset(wsteth), amountIn, "");

        IVault.FundManagement memory fundManagement =
            IVault.FundManagement(fromAddress, false, payable(toAddress), false);

        IERC20(weth).approve(address(self), amountIn);

        return self.swap(singleSwap, fundManagement, minAmountOut, deadline);
    }

    function swapWstEthToWeth(
        IVault self,
        address fromAddress,
        address toAddress,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) public returns (uint256) {
        IVault.SingleSwap memory singleSwap =
            IVault.SingleSwap(wethwstethPool, IVault.SwapKind.GIVEN_IN, IAsset(wsteth), IAsset(weth), amountIn, "");

        IVault.FundManagement memory fundManagement =
            IVault.FundManagement(fromAddress, false, payable(toAddress), false);

        IERC20(weth).approve(address(self), amountIn);

        return self.swap(singleSwap, fundManagement, minAmountOut, deadline);
    }
}

