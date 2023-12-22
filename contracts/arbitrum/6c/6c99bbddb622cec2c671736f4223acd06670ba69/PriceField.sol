// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./Math.sol";
import "./IConfig.sol";
import "./IPriceField.sol";

contract PriceField is IPriceField {
    uint128 public constant PRICE_PRECISION = 1e18;

    uint128 public constant PRECENT_DENOMINATOR = 10000000000;

    IConfig private _config;

    // main slope
    // 10 decimals
    uint256 private _slope;

    //
    uint256 private _exerciseAmount;

    // current floor price
    uint256 private _floorPrice;

    constructor(IConfig config_, uint256 slope_, uint256 floorPrice_) {
        _config = config_;
        _slope = slope_;
        _exerciseAmount = 0;

        _setFloorPrice(floorPrice_);
    }

    modifier onlyVamm() {
        require(
            msg.sender == address(_config.getVAMMAddress()),
            "PriceField: caller is not the vamm"
        );
        _;
    }

    function _setFloorPrice(uint256 floorPrice_) internal {
        require(floorPrice_ >= PRICE_PRECISION / 2, "floor price too low");
        require(floorPrice_ > _floorPrice, "floor price too low");
        uint256 x3 = _config.getUtilityToken().totalSupply();
        if (x3 > c()) {
            uint256 maxFloorPrice = (Math.mulDiv(
                x3 - c(),
                _slope,
                PRECENT_DENOMINATOR,
                Math.Rounding.Zero
            ) + PRICE_PRECISION) / 2;
            _floorPrice = Math.min(floorPrice_, maxFloorPrice);
        } else if (_floorPrice == 0) {
            _floorPrice = floorPrice_;
        } else if (x3 > x1(floorPrice_) + _exerciseAmount) {
            _floorPrice = floorPrice_;
        } else if (x3 == 0) {
            _floorPrice = floorPrice_;
        }
        emit UpdateFloorPrice(_floorPrice);
    }

    function setFloorPrice(uint256 floorPrice_) external onlyVamm {
        _setFloorPrice(floorPrice_);
    }

    function increaseSupplyWithNoPriceImpact(uint256 amount) external onlyVamm {
        _exerciseAmount += amount;
    }

    function exerciseAmount() external view returns (uint256) {
        return _exerciseAmount;
    }

    function slope() external view returns (uint256) {
        return _slope;
    }

    function slope0() external view returns (uint256) {
        uint256 a = _floorPrice;
        uint256 b = _finalPrice1(x2() + _exerciseAmount, false);
        uint256 h = x2() - x1();
        return Math.mulDiv(b - a, PRECENT_DENOMINATOR, h);
    }

    function floorPrice() external view returns (uint256) {
        return _floorPrice;
    }

    function x1(uint256 targetFloorPrice) public view returns (uint256) {
        // (2fp - 1)/m
        return
            Math.mulDiv(
                (targetFloorPrice * 2 - PRICE_PRECISION),
                PRECENT_DENOMINATOR,
                _slope,
                Math.Rounding.Zero
            );
    }

    function x1() public view returns (uint256) {
        // (2fp - 1)/m
        return
            Math.mulDiv(
                (_floorPrice * 2 - PRICE_PRECISION),
                PRECENT_DENOMINATOR,
                _slope,
                Math.Rounding.Zero
            );
    }

    function x2() public view returns (uint256) {
        // x2 = x1+2/m
        return x1() + c();
    }

    function c() public view returns (uint256) {
        // 2/m
        return
            Math.mulDiv(
                2 * PRICE_PRECISION,
                PRECENT_DENOMINATOR,
                _slope,
                Math.Rounding.Zero
            );
    }

    function c1() public view returns (uint256) {
        // x1 + 1/m
        return
            x1() +
            Math.mulDiv(
                PRICE_PRECISION,
                PRECENT_DENOMINATOR,
                _slope,
                Math.Rounding.Zero
            );
    }

    function b2() public view returns (uint256) {
        // m*x2
        return Math.mulDiv(x2(), _slope, PRECENT_DENOMINATOR, Math.Rounding.Up);
    }

    function k() public view returns (uint256) {
        // b2-fp
        return b2() - _floorPrice;
    }

    function finalPrice1(
        uint256 x,
        bool round
    ) external view returns (uint256) {
        return _finalPrice1(x, round);
    }

    function finalPrice2(
        uint256 x,
        bool round
    ) external view returns (uint256) {
        return _finalPrice2(x, round);
    }

    function _finalPrice1(
        uint256 x,
        bool round
    ) internal view returns (uint256) {
        require(x >= x1() + _exerciseAmount, "x too low");
        require(x <= x2() + _exerciseAmount, "x too high");
        if (x < c1() + _exerciseAmount) {
            return
                Math.mulDiv(
                    PRICE_PRECISION -
                        Math.mulDiv(
                            c1() + _exerciseAmount - x,
                            _slope,
                            PRECENT_DENOMINATOR,
                            round ? Math.Rounding.Up : Math.Rounding.Zero
                        ),
                    k(),
                    2 * PRICE_PRECISION
                ) + _floorPrice;
        }
        // ((x-c1-s) * m + 1) * k / 2 + fp
        return
            Math.mulDiv(
                Math.mulDiv(
                    x - c1() - _exerciseAmount,
                    _slope,
                    PRECENT_DENOMINATOR,
                    round ? Math.Rounding.Up : Math.Rounding.Zero
                ) + PRICE_PRECISION,
                k(),
                2 * PRICE_PRECISION
            ) + _floorPrice;
    }

    function _finalPrice2(
        uint256 x,
        bool round
    ) internal view returns (uint256) {
        require(x >= x2() + _exerciseAmount, "x too low");
        // (x-s) * m
        return
            Math.mulDiv(
                x - _exerciseAmount,
                _slope,
                PRECENT_DENOMINATOR,
                round ? Math.Rounding.Up : Math.Rounding.Zero
            );
    }

    function getPrice1(
        uint256 xs,
        uint256 xe,
        bool round
    ) external view returns (uint256) {
        return _getPrice1(xs, xe, round);
    }

    function getPrice2(
        uint256 xs,
        uint256 xe,
        bool round
    ) external view returns (uint256) {
        return _getPrice2(xs, xe, round);
    }

    // Calculate the total price of the price1 based on two points
    function _getPrice1(
        uint256 xs,
        uint256 xe,
        bool round
    ) internal view returns (uint256) {
        require(xs <= xe, "xs > xe");
        uint256 p1xs = xs;
        uint256 p1xe = xe;

        if (xs > x2() + _exerciseAmount) {
            return 0;
        }

        if (xe < x1() + _exerciseAmount) {
            return 0;
        }

        if (xs < x1() + _exerciseAmount) {
            p1xs = x1() + _exerciseAmount;
        }

        if (xe > x2() + _exerciseAmount) {
            p1xe = x2() + _exerciseAmount - 1;
        }

        uint256 a = _finalPrice1(p1xs, round);
        uint256 b = _finalPrice1(p1xe, round);

        return
            Math.mulDiv(
                a + b,
                p1xe - p1xs,
                2 * PRICE_PRECISION,
                round ? Math.Rounding.Up : Math.Rounding.Zero
            );
    }

    // Calculate the total price of the price2 based on two points
    function _getPrice2(
        uint256 xs,
        uint256 xe,
        bool round
    ) internal view returns (uint256) {
        require(xs <= xe, "xs > xe");

        if (xe < x2() + _exerciseAmount) {
            return 0;
        }
        
        uint256 p2xs = xs;
        uint256 p2xe = xe;

        if (xs < x2() + _exerciseAmount) {
            p2xs = x2() + _exerciseAmount;
        }

        uint256 a = _finalPrice2(p2xs, round);
        uint256 b = _finalPrice2(p2xe, round);

        return
            Math.mulDiv(
                a + b,
                p2xe - p2xs,
                2 * PRICE_PRECISION,
                round ? Math.Rounding.Up : Math.Rounding.Zero
            );
    }

    // Calculate the total price of the floor price based on two points
    function _getPrice0(
        uint256 xs,
        uint256 xe,
        bool round
    ) internal view returns (uint256) {
        require(xs <= xe, "xs > xe");
        uint256 fpAmount = 0;
        if (xs < x1() + _exerciseAmount) {
            fpAmount = x1() + _exerciseAmount - xs;
        }
        if (xe < x1() + _exerciseAmount) {
            fpAmount = xe - xs;
        }

        return
            Math.mulDiv(
                fpAmount,
                _floorPrice,
                PRICE_PRECISION,
                round ? Math.Rounding.Up : Math.Rounding.Zero
            );
    }

    function getUseFPBuyPrice(
        uint256 amount
    ) public view returns (uint256 toLiquidityPrice, uint256 fees) {
        toLiquidityPrice = Math.mulDiv(
            _floorPrice,
            amount,
            PRICE_PRECISION,
            Math.Rounding.Up
        );
        fees = _config.vammBuyFees(toLiquidityPrice);
    }

    function getBuyPrice(
        uint256 amount
    ) external view returns (uint256 toLiquidityPrice, uint256 fees) {
        uint256 xs = _config.getUtilityToken().totalSupply() + 1;
        uint256 xe = xs + amount;
        uint256 price1 = _getPrice1(xs, xe, true);
        uint256 price2 = _getPrice2(xs, xe, true);
        uint256 price0 = _getPrice0(xs, xe, true);
        toLiquidityPrice = price1 + price2 + price0;
        fees = _config.vammBuyFees(toLiquidityPrice);
    }

    function getSellPrice(
        uint256 xe,
        uint256 amount
    ) external view returns (uint256 toUserPrice, uint256 fees) {
        uint256 xs = xe - amount;
        uint256 price1 = _getPrice1(xs, xe, false);
        uint256 price2 = _getPrice2(xs, xe, false);
        uint256 price0 = _getPrice0(xs, xe, false);
        uint256 totalPrice = price1 + price2 + price0;
        fees = _config.vammSellFees(totalPrice);
        toUserPrice = totalPrice - fees;
    }

    function getSellPrice(
        uint256 amount
    ) external view returns (uint256 toUserPrice, uint256 fees) {
        uint256 xe = _config.getUtilityToken().totalSupply();
        if (xe == 0) {
            return (0, 0);
        }
        uint256 xs = xe - amount;
        uint256 price1 = _getPrice1(xs, xe, false);
        uint256 price2 = _getPrice2(xs, xe, false);
        uint256 price0 = _getPrice0(xs, xe, false);
        uint256 totalPrice = price1 + price2 + price0;
        fees = _config.vammSellFees(totalPrice);
        toUserPrice = totalPrice - fees;
    }
}

