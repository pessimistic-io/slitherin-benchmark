// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ICollateral } from "./ICollateral.sol";
import { IBorrowable } from "./IBorrowable.sol";
import { IUniswapV2Pair } from "./IUniswapV2Pair.sol";
import { IERC20, SafeERC20 } from "./SafeERC20.sol";

contract LeverageBorrow {

    enum Operation { NULL, DEFAULT, CREATE, REPAY_BORROWABLE }
    struct TempSlot {
        address sender;
        Operation operation;
    }

    TempSlot temp = TempSlot(address(0xdead), Operation.DEFAULT);

    // prerequisites:
    // approve base asset to this contract
    // approve borrow to this contract, see tests
    function createLeveragedPosition(uint baseAssetAmount, address flashloanSource, address collateral) external {
        address vault = ICollateral(collateral).underlying();
        address lp; bool baseIs0;
        {
            (bool success, bytes memory lpBytes) = vault.staticcall(abi.encodeWithSignature("underlying()"));
            lp = success ? abi.decode(lpBytes, (address)) : vault;
            baseIs0 = IUniswapV2Pair(lp).token1() == IBorrowable(flashloanSource).underlying();
        }

        uint baseReserve;
        uint volatileReserve;

        (bool isSolidlyFork, bytes memory reserveBytes) = lp.staticcall(abi.encodeWithSignature("reserve0()"));

        if (isSolidlyFork) {
            if (baseIs0) {
                baseReserve = abi.decode(reserveBytes, (uint));
                volatileReserve = IUniswapV2Pair(lp).reserve1();
            } else {
                baseReserve = IUniswapV2Pair(lp).reserve1();
                volatileReserve = abi.decode(reserveBytes, (uint));
            }
        } else {
            (uint112 r0, uint112 r1, ) = IUniswapV2Pair(lp).getReserves();
            if (baseIs0) {
                (baseReserve, volatileReserve) = (r0, r1);
            } else {
                (baseReserve, volatileReserve) = (r1, r0);
            }
        }

        SafeERC20.safeTransferFrom(IERC20(baseIs0 ? IUniswapV2Pair(lp).token0() : IUniswapV2Pair(lp).token1()), msg.sender, lp, baseAssetAmount);

        uint volatileToBorrow = baseAssetAmount * volatileReserve / baseReserve;

        temp = TempSlot(msg.sender, Operation.CREATE);

        IBorrowable(flashloanSource).borrow(address(this), address(this), volatileToBorrow, abi.encode( collateral, vault, lp, baseIs0));
        temp = TempSlot(address(0xdead), Operation.DEFAULT);
    }

    // prerequisites:
    // approve collateral to this contract
    function repayLeveragedPosition(uint repaymentAmount, address flashloanSource, address collateral) external {
        address vault = ICollateral(collateral).underlying();
        address lp; bool baseIs0;
        {
            (bool success, bytes memory lpBytes) = vault.staticcall(abi.encodeWithSignature("underlying()"));
            lp = success ? abi.decode(lpBytes, (address)) : vault;
            baseIs0 = IUniswapV2Pair(lp).token1() == IBorrowable(flashloanSource).underlying();
        }

        uint volatileReserve;
        uint lpSupply = IUniswapV2Pair(lp).totalSupply();

        (bool isSolidlyFork, bytes memory reserveBytes) = lp.staticcall(abi.encodeWithSignature("reserve0()"));

        if (isSolidlyFork) {
            if (baseIs0) {
                volatileReserve = IUniswapV2Pair(lp).reserve1();
            } else {
                volatileReserve = abi.decode(reserveBytes, (uint));
            }
        } else {
            (uint112 r0, uint112 r1, ) = IUniswapV2Pair(lp).getReserves();
            if (baseIs0) {
                volatileReserve = r1;
            } else {
                volatileReserve = r0;
            }
        }

        uint collateralToWithdraw =
            lpSupply * repaymentAmount / volatileReserve
            * 1e18 / (lp == vault ? 1e18 : ICollateral(vault).exchangeRate())
            * 1e18 / ICollateral(collateral).exchangeRate()
            * 1001 / 1000;

//        {
//            uint balance = ICollateral(collateral).balanceOf(msg.sender);
//            if (collateralToWithdraw > balance) {
//                collateralToWithdraw = balance;
//            }
//        }

        // safety measure
        temp = TempSlot(msg.sender, Operation.REPAY_BORROWABLE);

        IBorrowable(flashloanSource)
            .borrow(address(this), address(this), repaymentAmount, abi.encode(collateral, vault, lp, collateralToWithdraw, baseIs0));

        // safety measure
        temp = TempSlot(address(0xdead), Operation.DEFAULT);
    }

    function impermaxBorrow(address, address, uint amountBorrowed, bytes memory data) external {
        _processFlashloanBorrowable(amountBorrowed, data);
    }

    function tarotBorrow(address, address, uint amountBorrowed, bytes memory data) external {
        _processFlashloanBorrowable(amountBorrowed, data);
    }

    function _processFlashloanBorrowable(uint flashloanAmount, bytes memory data) internal {
        TempSlot memory _temp = temp;
        if (_temp.operation == Operation.CREATE) {
            address targetBorrowable = _create(_temp.sender, flashloanAmount, data);
            IBorrowable(targetBorrowable).borrow(_temp.sender, msg.sender, flashloanAmount + flashloanAmount * IBorrowable(msg.sender).BORROW_FEE() / 1e18, new bytes(0));
        } else {
            _repay(_temp.sender, flashloanAmount, data);
        }
    }

    function _create(address owner, uint flashloanAmount, bytes memory data) internal returns(address) {
        (address collateral, address vault, address lp, bool baseIs0) = abi.decode(data, (address, address, address, bool));

        address volatileToken = IBorrowable(msg.sender).underlying();
        SafeERC20.safeTransfer(IERC20(volatileToken), lp, flashloanAmount);
        if (vault != lp) {
            IUniswapV2Pair(lp).mint(vault);
            ICollateral(vault).mint(collateral);
        } else {
            IUniswapV2Pair(lp).mint(collateral);
        }
        ICollateral(collateral).mint(owner);
        return baseIs0 ? ICollateral(collateral).borrowable0() : ICollateral(collateral).borrowable0();
    }

    function _repay(address owner, uint flashloanAmount, bytes memory data) internal {
        (address collateral, address vault, address lp, uint collateralToWithdraw, bool baseIs0) = abi.decode(data, (address, address, address, uint, bool));
        address volatileToken = IBorrowable(msg.sender).underlying();

        address baseAsset;
        address repayingBorrowable;

        if (baseIs0) {
            baseAsset = IBorrowable(ICollateral(collateral).borrowable0()).underlying();
            repayingBorrowable = ICollateral(collateral).borrowable1();
        } else {
            baseAsset = IBorrowable(ICollateral(collateral).borrowable1()).underlying();
            repayingBorrowable = ICollateral(collateral).borrowable0();
        }

        SafeERC20.safeTransfer(IERC20(volatileToken), repayingBorrowable, flashloanAmount);
        IBorrowable(repayingBorrowable).borrow(owner, owner, 0, new bytes(0));

        ICollateral(collateral).transferFrom(owner, collateral, collateralToWithdraw);

        ICollateral(collateral).redeem(vault);

        if (vault != lp) {
            ICollateral(vault).redeem(lp);
        }

        IUniswapV2Pair(lp).burn(address(this));

        uint amountToReturn = flashloanAmount + flashloanAmount * IBorrowable(msg.sender).BORROW_FEE() / 1e18;

        SafeERC20.safeTransfer(IERC20(volatileToken), msg.sender, amountToReturn);
        SafeERC20.safeTransfer(IERC20(baseAsset), owner, IERC20(baseAsset).balanceOf(address(this)));
    }
}

