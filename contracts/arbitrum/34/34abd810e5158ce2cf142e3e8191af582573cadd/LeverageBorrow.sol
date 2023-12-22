// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ICollateral } from "./ICollateral.sol";
import { IBorrowable } from "./IBorrowable.sol";
import { IUniswapV2Pair } from "./IUniswapV2Pair.sol";
import { IERC20, SafeERC20 } from "./SafeERC20.sol";

contract LeverageBorrow {

    address temp = address(0xdead);

    // prerequisites:
    // approve usdc to this contract
    // approve borrow to this contract, see tests
    function createLeveragedPosition(uint stablecoinAmount, address flashloanSource, address collateral) external {
        address vault = ICollateral(collateral).underlying();
        address lp; bool stableIs0;
        {
            (bool success, bytes memory lpBytes) = vault.staticcall(abi.encodeWithSignature("underlying()"));
            lp = success ? abi.decode(lpBytes, (address)) : vault;
            stableIs0 = IUniswapV2Pair(lp).token1() == IBorrowable(flashloanSource).underlying();
        }

        uint stableReserve;
        uint volatileReserve;

        (bool isSolidlyFork, bytes memory reserveBytes) = lp.staticcall(abi.encodeWithSignature("reserve0()"));

        if (isSolidlyFork) {
            if (stableIs0) {
                stableReserve = abi.decode(reserveBytes, (uint));
                volatileReserve = IUniswapV2Pair(lp).reserve1();
            } else {
                stableReserve = IUniswapV2Pair(lp).reserve1();
                volatileReserve = abi.decode(reserveBytes, (uint));
            }
        } else {
            (uint112 r0, uint112 r1, ) = IUniswapV2Pair(lp).getReserves();
            if (stableIs0) {
                (stableReserve, volatileReserve) = (r0, r1);
            } else {
                (stableReserve, volatileReserve) = (r1, r0);
            }
        }

        SafeERC20.safeTransferFrom(IERC20(stableIs0 ? IUniswapV2Pair(lp).token0() : IUniswapV2Pair(lp).token1()), msg.sender, lp, stablecoinAmount);

        uint volatileToBorrow = stablecoinAmount * volatileReserve / stableReserve;

        temp = msg.sender;
        IBorrowable(flashloanSource).borrow(address(this), address(this), volatileToBorrow, abi.encode( collateral, vault, lp, stableIs0));
        temp = address(0xdead);
    }

    function impermaxBorrow(address, address, uint amountBorrowed, bytes memory data) external {
        _processFlashloan(amountBorrowed, data);
    }

    function tarotBorrow(address, address, uint amountBorrowed, bytes memory data) external {
        _processFlashloan(amountBorrowed, data);
    }

    function _processFlashloan(uint amountBorrowed, bytes memory data) internal {
        (address collateral, address vault, address lp, bool usdcIs0) = abi.decode(data, (address, address, address, bool));
        address owner = temp;
        address volatileToken = IBorrowable(msg.sender).underlying();
        SafeERC20.safeTransfer(IERC20(volatileToken), lp, amountBorrowed);
        IUniswapV2Pair(lp).mint(vault);
        if (vault != collateral) {
            ICollateral(vault).mint(collateral);
        }
        ICollateral(collateral).mint(owner);

        uint amountToReturn = amountBorrowed + amountBorrowed * IBorrowable(msg.sender).BORROW_FEE() / 1e18;

        IBorrowable(usdcIs0 ? ICollateral(collateral).borrowable0() : ICollateral(collateral).borrowable0()).borrow(owner, msg.sender, amountToReturn, new bytes(0));
    }
}

// Built with ❤️ by Chainpioneer

