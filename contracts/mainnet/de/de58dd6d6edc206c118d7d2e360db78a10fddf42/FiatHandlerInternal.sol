/*
 * This file is part of the Qomet Technologies contracts (https://github.com/qomet-tech/contracts).
 * Copyright (c) 2022 Qomet Technologies (https://qomet.tech)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
// SPDX-License-Identifier: GNU General Public License v3.0

pragma solidity 0.8.1;

import "./IERC20.sol";
import "./FiatHandlerStorage.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";

/// @author Kam Amini <kam@arteq.io>
///
/// @notice Use at your own risk
library FiatHandlerInternal {

    event WeiDiscount(
        uint256 indexed payId,
        address indexed payer,
        uint256 totalMicroUSDAmountBeforeDiscount,
        uint256 totalWeiBeforeDiscount,
        uint256 discountWei
    );
    event WeiPay(
        uint256 indexed payId,
        address indexed payer,
        address indexed dest,
        uint256 totalMicroUSDAmountBeforeDiscount,
        uint256 totalWeiAfterDiscount
    );
    event Erc20Discount(
        uint256 indexed payId,
        address indexed payer,
        uint256 totalMicroUSDAmountBeforeDiscount,
        address indexed erc20,
        uint256 totalTokensBeforeDiscount,
        uint256 discountTokens
    );
    event Erc20Pay(
        uint256 indexed payId,
        address indexed payer,
        address indexed dest,
        uint256 totalMicroUSDAmountBeforeDiscount,
        address erc20,
        uint256 totalTokensAfterDiscount
    );
    event TransferWeiTo(
        address indexed to,
        uint256 indexed amount
    );
    event TransferErc20To(
        address indexed erc20,
        address indexed to,
        uint256 amount
    );

    modifier mustBeInitialized() {
        require(__s().initialized, "FHI:NI");
        _;
    }

    function _initialize(
        address uniswapV2Factory,
        address wethAddress,
        address microUSDAddress,
        uint256 maxNegativeSlippage
    ) internal {
        require(!__s().initialized, "CI:AI");
        require(uniswapV2Factory != address(0), "FHI:ZFA");
        require(wethAddress != address(0), "FHI:ZWA");
        require(microUSDAddress != address(0), "FHI:ZMUSDA");
        require(maxNegativeSlippage >= 0 && maxNegativeSlippage <= 10, "FHI:WMNS");
        __s().uniswapV2Factory = uniswapV2Factory;
        __s().wethAddress = wethAddress;
        __s().microUSDAddress = microUSDAddress;
        __s().maxNegativeSlippage = maxNegativeSlippage;
        __s().payIdCounter = 1000;
        // by default allow WETH and USDT
        _setErc20Allowed(wethAddress, true);
        _setErc20Allowed(microUSDAddress, true);
        __s().initialized = true;
    }

    function _getFiatHandlerSettings()
    internal view returns (
        address, // uniswapV2Factory
        address, // wethAddress
        address, // microUSDAddress
        uint256  // maxNegativeSlippage
    ) {
        return (
            __s().uniswapV2Factory,
            __s().wethAddress,
            __s().microUSDAddress,
            __s().maxNegativeSlippage
        );
    }

    function _setFiatHandlerSettings(
        address uniswapV2Factory,
        address wethAddress,
        address microUSDAddress,
        uint256 maxNegativeSlippage
    ) internal mustBeInitialized {
        require(uniswapV2Factory != address(0), "FHI:ZFA");
        require(wethAddress != address(0), "FHI:ZWA");
        require(microUSDAddress != address(0), "FHI:ZMUSDA");
        require(maxNegativeSlippage >= 0 && maxNegativeSlippage <= 10, "FHI:WMNS");
        __s().wethAddress = wethAddress;
        __s().microUSDAddress = microUSDAddress;
        __s().maxNegativeSlippage = maxNegativeSlippage;
        __s().maxNegativeSlippage = maxNegativeSlippage;
    }

    function _getDiscount(address erc20) internal view returns (bool, bool, uint256, uint256) {
        FiatHandlerStorage.Discount storage discount;
        if (erc20 == address(0)) {
            discount = __s().weiDiscount;
        } else {
            discount = __s().erc20Discounts[erc20];
        }
        return (
            discount.enabled,
            discount.useFixed,
            discount.discountF,
            discount.discountP
        );
    }

    function _setDiscount(
        address erc20,
        bool enabled,
        bool useFixed,
        uint256 discountF,
        uint256 discountP
    ) internal {
        require(discountP >= 0 && discountP <= 100, "FHI:WDP");
        FiatHandlerStorage.Discount storage discount;
        if (erc20 == address(0)) {
            discount = __s().weiDiscount;
        } else {
            discount = __s().erc20Discounts[erc20];
        }
        discount.enabled = enabled;
        discount.useFixed = useFixed;
        discount.discountF = discountF;
        discount.discountP = discountP;
    }

    function _getListOfErc20s() internal view returns (address[] memory) {
        return __s().erc20sList;
    }

    function _isErc20Allowed(address erc20) internal view returns (bool) {
        return __s().allowedErc20s[erc20];
    }

    function _setErc20Allowed(address erc20, bool allowed) internal {
        __s().allowedErc20s[erc20] = allowed;
        if (__s().erc20sListIndex[erc20] == 0) {
            __s().erc20sList.push(erc20);
            __s().erc20sListIndex[erc20] = __s().erc20sList.length;
        }
    }

    function _transferTo(
        address erc20,
        address to,
        uint256 amount,
        string memory /* data */
    ) internal {
        require(to != address(0), "FHI:TTZ");
        require(amount > 0, "FHI:ZAM");
        if (erc20 == address(0)) {
            require(amount <= address(this).balance, "FHI:MTB");
            /* solhint-disable avoid-low-level-calls */
            (bool success, ) = to.call{value: amount}(new bytes(0));
            /* solhint-enable avoid-low-level-calls */
            require(success, "FHI:TF");
            emit TransferWeiTo(to, amount);
        } else {
            require(amount <= IERC20(erc20).balanceOf(address(this)), "FHI:MTB");
            bool success = IERC20(erc20).transfer(to, amount);
            require(success, "FHI:TF2");
            emit TransferErc20To(erc20, to, amount);
        }
    }

    struct PayParams {
        address erc20;
        address payer;
        address payout;
        uint256 microUSDAmount;
        uint256 availableValue;
        bool returnRemainder;
        bool considerDiscount;
    }
    function _pay(
        PayParams memory params
    ) internal mustBeInitialized returns (uint256) {
        require(params.payer != address(0), "FHI:ZP");
        if (params.microUSDAmount == 0) {
            return 0;
        }
        if (params.erc20 != address(0)) {
            require(__s().allowedErc20s[params.erc20], "FHI:CNA");
        }
        uint256 payId = __s().payIdCounter + 1;
        __s().payIdCounter += 1;
        address dest = address(this);
        if (params.payout != address(0)) {
            dest = params.payout;
        }
        if (params.erc20 == address(0)) {
            uint256 weiAmount = _convertMicroUSDToWei(params.microUSDAmount);
            uint256 discount = 0;
            if (params.considerDiscount) {
                discount = _calcDiscount(address(0), weiAmount);
            }
            if (discount > 0) {
                emit WeiDiscount(
                    payId, params.payer, params.microUSDAmount, weiAmount, discount);
                weiAmount -= discount;
            }
            if (params.availableValue < weiAmount) {
                uint256 diff = weiAmount - params.availableValue;
                uint256 slippage = (diff * 100) / weiAmount;
                require(slippage < __s().maxNegativeSlippage, "FHI:XMNS");
                return 0;
            }
            if (dest != address(this) && weiAmount > 0) {
                /* solhint-disable avoid-low-level-calls */
                (bool success,) = dest.call{value: weiAmount}(new bytes(0));
                /* solhint-enable avoid-low-level-calls */
                require(success, "FHI:TRF");
            }
            emit WeiPay(payId, params.payer, dest, params.microUSDAmount, weiAmount);
            if (params.returnRemainder && params.availableValue >= weiAmount) {
                uint256 remainder = params.availableValue - weiAmount;
                if (remainder > 0) {
                    /* solhint-disable avoid-low-level-calls */
                    (bool success2, ) = params.payer.call{value: remainder}(new bytes(0));
                    /* solhint-enable avoid-low-level-calls */
                    require(success2, "FHI:TRF2");
                }
            }
            return weiAmount;
        } else {
            uint256 tokensAmount = _convertMicroUSDToERC20(params.erc20, params.microUSDAmount);
            uint256 discount = 0;
            if (params.considerDiscount) {
                discount = _calcDiscount(params.erc20, tokensAmount);
            }
            if (discount > 0) {
                emit Erc20Discount(
                    payId, params.payer, params.microUSDAmount, params.erc20, tokensAmount, discount);
                tokensAmount -= discount;
            }
            require(tokensAmount <=
                    IERC20(params.erc20).balanceOf(params.payer), "FHI:NEB");
            require(tokensAmount <=
                    IERC20(params.erc20).allowance(params.payer, address(this)), "FHI:NEA");
            if (tokensAmount > 0) {
                IERC20(params.erc20).transferFrom(params.payer, dest, tokensAmount);
            }
            emit Erc20Pay(
                payId, params.payer, dest, params.microUSDAmount, params.erc20, tokensAmount);
            return 0;
        }
    }

    function _convertMicroUSDToWei(uint256 microUSDAmount) internal view returns (uint256) {
        require(__s().wethAddress != address(0), "FHI:ZWA");
        require(__s().microUSDAddress != address(0), "FHI:ZMUSDA");
        (bool pairFound, uint256 wethReserve, uint256 microUSDReserve) =
            __getReserves(__s().wethAddress, __s().microUSDAddress);
        require(pairFound && microUSDReserve > 0, "FHI:NPF");
        return (microUSDAmount * wethReserve) / microUSDReserve;
    }

    function _convertWeiToMicroUSD(uint256 weiAmount) internal view returns (uint256) {
        require(__s().wethAddress != address(0), "FHI:ZWA");
        require(__s().microUSDAddress != address(0), "FHI:ZMUSDA");
        (bool pairFound, uint256 wethReserve, uint256 microUSDReserve) =
            __getReserves(__s().wethAddress, __s().microUSDAddress);
        require(pairFound && wethReserve > 0, "FHI:NPF");
        return (weiAmount * microUSDReserve) / wethReserve;
    }

    function _convertMicroUSDToERC20(
        address erc20,
        uint256 microUSDAmount
    ) internal view returns (uint256) {
        require(__s().microUSDAddress != address(0), "FHI:ZMUSDA");
        if (erc20 == __s().microUSDAddress) {
            return microUSDAmount;
        }
        (bool microUSDPairFound, uint256 microUSDReserve, uint256 tokensReserve) =
            __getReserves(__s().microUSDAddress, erc20);
        if (microUSDPairFound && microUSDReserve > 0) {
            return (microUSDAmount * tokensReserve) / microUSDReserve;
        } else {
            require(__s().wethAddress != address(0), "FHI:ZWA");
            (bool pairFound, uint256 wethReserve, uint256 microUSDReserve2) =
                __getReserves(__s().wethAddress, __s().microUSDAddress);
            require(pairFound && microUSDReserve2 > 0, "FHI:NPF");
            uint256 weiAmount = (microUSDAmount * wethReserve) / microUSDReserve2;
            (bool wethPairFound, uint256 wethReserve2, uint256 tokensReserve2) =
                __getReserves(__s().wethAddress, erc20);
            require(wethPairFound && wethReserve2 > 0, "FHI:NPF2");
            return (weiAmount * tokensReserve2) / wethReserve2;
        }
    }

    function _convertERC20ToMicroUSD(
        address erc20,
        uint256 tokensAmount
    ) internal view returns (uint256) {
        require(__s().microUSDAddress != address(0), "FHI:ZMUSDA");
        if (erc20 == __s().microUSDAddress) {
            return tokensAmount;
        }
        (bool microUSDPairFound, uint256 microUSDReserve, uint256 tokensReserve) =
            __getReserves(__s().microUSDAddress, erc20);
        if (microUSDPairFound && tokensReserve > 0) {
            return (tokensAmount * microUSDReserve) / tokensReserve;
        } else {
            require(__s().wethAddress != address(0), "FHI:ZWA");
            (bool wethPairFound, uint256 wethReserve, uint256 tokensReserve2) =
                __getReserves(__s().wethAddress, erc20);
            require(wethPairFound && wethReserve > 0, "FHI:NPF");
            uint256 weiAmount = (tokensAmount * wethReserve) / tokensReserve2;
            (bool pairFound, uint256 wethReserve2, uint256 microUSDReserve2) =
                __getReserves(__s().wethAddress, __s().microUSDAddress);
            require(pairFound && wethReserve2 > 0, "FHI:NPF2");
            return (weiAmount * microUSDReserve2) / wethReserve2;
        }
    }

    function _calcDiscount(
        address erc20,
        uint256 amount
    ) internal view returns (uint256) {
        FiatHandlerStorage.Discount storage discount;
        if (erc20 == address(0)) {
            discount = __s().weiDiscount;
        } else {
            discount = __s().erc20Discounts[erc20];
        }
        if (!discount.enabled) {
            return 0;
        }
        if (discount.useFixed) {
            if (amount < discount.discountF) {
                return amount;
            }
            return discount.discountF;
        }
        return (amount * discount.discountP) / 100;
    }

    function __getReserves(
        address erc200,
        address erc201
    ) private view returns (bool, uint256, uint256) {
        address pair = IUniswapV2Factory(
            __s().uniswapV2Factory).getPair(erc200, erc201);
        if (pair == address(0)) {
            return (false, 0, 0);
        }
        address token1 = IUniswapV2Pair(pair).token1();
        (uint112 amount0, uint112 amount1,) = IUniswapV2Pair(pair).getReserves();
        uint256 reserve0 = amount0;
        uint256 reserve1 = amount1;
        if (token1 == erc200) {
            reserve0 = amount1;
            reserve1 = amount0;
        }
        return (true, reserve0, reserve1);
    }

    function __s() private pure returns (FiatHandlerStorage.Layout storage) {
        return FiatHandlerStorage.layout();
    }
}

