// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UniswapV3Library, ISwapRouter} from "./UniswapV3.sol";
import {FullMath} from "./UniswapV3.sol";
import "./CommonModule.sol";
import "./IInchConversion.sol";
import "./console.sol";

abstract contract SwapModule is CommonModule {

    address public uniswapV3Router;
    uint24 public poolFee0;
    uint24 public poolFee1;
    address public middleTokenAddress;
    uint256 public allowedSlippageBp;
    address public inchRouter;

    function _getSwapLiquidity() internal view returns (uint256 baseBalance, uint256 sideBalance) {
        return UniswapV3SwapLibrary._getLiquidity(this);
    }

    function _swapByInchRoute(CompoundSwap memory compoundSwap, RevertParams memory revertParams) internal {
        UniswapV3SwapLibrary._swapByInchRoute(this, compoundSwap, revertParams);
    }

    function _swapSideToBase(uint256 delta) internal {
        UniswapV3SwapLibrary._swapSideToBase(this, delta);
    }

    function _swapBaseToSide(uint256 delta) internal {
        UniswapV3SwapLibrary._swapBaseToSide(this, delta);
    }

    uint256[49] private __gap;
}


library UniswapV3SwapLibrary {

    event Conversion(address assetFrom, address assetTo, uint256 amountIn, uint256 amountOut);
    event InchConversion(address assetFrom, address assetTo, uint256 amountIn, uint256 amountOut);

    function _getLiquidity(SwapModule self) public view returns (uint256 baseBalance, uint256 sideBalance) {
        baseBalance = self.baseToken().balanceOf(address(self));
        sideBalance = self.sideToken().balanceOf(address(self));
    }

    function _swapByInchRoute(SwapModule self, CompoundSwap memory compoundSwap, RevertParams memory revertParams) public {
        compoundSwap.desc.dstReceiver = payable(address(self));
        self.baseToken().approve(self.inchRouter(), self.MAX_UINT_VALUE());
        self.sideToken().approve(self.inchRouter(), self.MAX_UINT_VALUE());
        
        IInchRouter router = IInchRouter(self.inchRouter());
        
        uint256 baseBalanceBefore = self.baseToken().balanceOf(address(self));
        uint256 sideBalanceBefore = self.sideToken().balanceOf(address(self));

        if (compoundSwap.isCommonSwap) {          
            router.swap(compoundSwap.caller, compoundSwap.desc, compoundSwap.data);
        } else {
            router.uniswapV3Swap(compoundSwap.amount, compoundSwap.minReturn, compoundSwap.pools);  
        }

        uint256 baseBalanceAfter = self.baseToken().balanceOf(address(self));
        uint256 sideBalanceAfter = self.sideToken().balanceOf(address(self));

        console.log("targetBalancePrice", revertParams.targetBalancePrice);

        if (baseBalanceBefore > baseBalanceAfter) {
            console.log("base to side", revertParams.isReverse);
            uint256 baseAmountIn = baseBalanceBefore - baseBalanceAfter;
            uint256 sideAmountOut = sideBalanceAfter - sideBalanceBefore;
            uint256 rate;
            if (revertParams.isReverse) {
                rate = FullMath.mulDiv(baseAmountIn * self.sideDecimals(), revertParams.poolDecimals, sideAmountOut * self.baseDecimals());
                console.log("rate", rate);
                require(revertParams.targetBalancePrice > rate || !revertParams.isRevertWhenBadRate, "bad rate for swap");
            } else {
                rate = FullMath.mulDiv(sideAmountOut * self.baseDecimals(), revertParams.poolDecimals, baseAmountIn * self.sideDecimals());
                console.log("rate", rate);
                require(revertParams.targetBalancePrice < rate || !revertParams.isRevertWhenBadRate, "bad rate for swap");
            }
            emit InchConversion(address(self.baseToken()), address(self.sideToken()), baseBalanceBefore - baseBalanceAfter, sideBalanceAfter - sideBalanceBefore);
        } else {
            console.log("side to base", revertParams.isReverse);
            uint256 sideAmountIn = sideBalanceBefore - sideBalanceAfter;
            uint256 baseAmountOut = baseBalanceAfter - baseBalanceBefore;            
            uint256 rate;
            if (revertParams.isReverse) {
                rate = FullMath.mulDiv(baseAmountOut * self.sideDecimals(), revertParams.poolDecimals, sideAmountIn * self.baseDecimals());
                console.log("rate", rate);
                require(revertParams.targetBalancePrice < rate || !revertParams.isRevertWhenBadRate, "bad rate for swap");
                
            } else {
                rate = FullMath.mulDiv(sideAmountIn * self.baseDecimals(), revertParams.poolDecimals, baseAmountOut * self.sideDecimals());
                console.log("rate", rate);
                require(revertParams.targetBalancePrice > rate || !revertParams.isRevertWhenBadRate, "bad rate for swap");
            }
            emit InchConversion(address(self.sideToken()), address(self.baseToken()), sideBalanceBefore - sideBalanceAfter, baseBalanceAfter - baseBalanceBefore);
        }
    }

    function _swapSideToBase(SwapModule self, uint256 delta) public {
        uint256 swapSideAmount = (delta == self.MAX_UINT_VALUE() || self.usdToSide(delta) > self.sideToken().balanceOf(address(self)))
                ? self.sideToken().balanceOf(address(self))
                : self.usdToSide(delta);
        if (self.sideToUsd(swapSideAmount) <= 10 ** 2) {
            return;
        }
        uint256 amountOutMin = self.usdToBase(self.sideToUsd(swapSideAmount / 10000 * (10000 - self.allowedSlippageBp())));
        uint256 amountOut;
        if (self.middleTokenAddress() == address(0)) {
            amountOut = UniswapV3Library.singleSwap(
                ISwapRouter(self.uniswapV3Router()),
                address(self.sideToken()),
                address(self.baseToken()),
                self.poolFee0(),
                address(self),
                swapSideAmount,
                amountOutMin
            );
        } else {
            amountOut = UniswapV3Library.multiSwap(
                ISwapRouter(self.uniswapV3Router()),
                address(self.sideToken()),
                self.middleTokenAddress(),
                address(self.baseToken()),
                self.poolFee1(),
                self.poolFee0(),
                address(self),
                swapSideAmount,
                amountOutMin
            );
        }

        emit Conversion(address(self.sideToken()), address(self.baseToken()), swapSideAmount, amountOut);
    }

    function _swapBaseToSide(SwapModule self, uint256 delta) public {
        uint256 swapBaseAmount = (delta == self.MAX_UINT_VALUE() || self.usdToBase(delta) > self.baseToken().balanceOf(address(self)))
                ? self.baseToken().balanceOf(address(self))
                : self.usdToBase(delta);
        if (self.baseToUsd(swapBaseAmount) <= 10 ** 2) {
            return;
        }

        uint256 amountOutMin = self.usdToSide(self.baseToUsd(swapBaseAmount / 10000 * (10000 - self.allowedSlippageBp())));
        uint256 amountOut;
        if (self.middleTokenAddress() == address(0)) {
            amountOut = UniswapV3Library.singleSwap(
                ISwapRouter(self.uniswapV3Router()),
                address(self.baseToken()),
                address(self.sideToken()),
                self.poolFee0(),
                address(self),
                swapBaseAmount,
                amountOutMin
            );
        } else {
            amountOut = UniswapV3Library.multiSwap(
                ISwapRouter(self.uniswapV3Router()),
                address(self.baseToken()),
                self.middleTokenAddress(),
                address(self.sideToken()),
                self.poolFee0(),
                self.poolFee1(),
                address(self),
                swapBaseAmount,
                amountOutMin
            );
        }

        emit Conversion(address(self.baseToken()), address(self.sideToken()), swapBaseAmount, amountOut);
    }
}

