// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;
import {IMarketValid} from "./IMarketValid.sol";

library MarketConfigStruct {
    using MarketConfigStruct for IMarketValid.Props;
    uint256 private constant MIN_SLIPPAGE_MASK =          0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000; // prettier-ignore
    uint256 private constant MAX_SLIPPAGE_MASK =          0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000FFF; // prettier-ignore
    uint256 private constant MIN_LEV_MASK =               0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000FFFFFF; // prettier-ignore
    uint256 private constant MAX_LEV_MASK =               0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000FFFFFFFFF; // prettier-ignore
    uint256 private constant MIN_PAY_MASK =               0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000FFFFFFFFFFFF; // prettier-ignore
    uint256 private constant MIN_COL_MASK =               0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000FFFFFFFFFFFFFFF; // prettier-ignore
    uint256 private constant MAX_TRADE_AMOUNT_MASK =      0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 private constant ALLOW_CLOSE_MASK =           0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0ffffffffFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 private constant ALLOW_OPEN_MASK =            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0fffffffffFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 private constant DECIMALS_MASK =              0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FfffffffffFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 private constant DECREASE_NUM_LIMIT_MASK =    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000FFFfffffffffFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 private constant VALID_DECREASE_MASK =        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0FFFFFFfffffffffFFFFFFFFFFFFFFFFFF; // prettier-ignore

    uint256 constant MAX_SLIPPAGE_BIT_POSITION = 3 * 4; // one digt = 0.5 byte = 4 bit
    uint256 constant MIN_LEV_BIT_POSITION = 3 * 4 * 2;
    uint256 constant MAX_LEV_BIT_POSITION = 3 * 4 * 3;
    uint256 constant MIN_PAY_BIT_POSITION = 3 * 4 * 4;
    uint256 constant MIN_COL_BIT_POSITION = 3 * 4 * 5;
    uint256 constant MAX_TRADE_AMOUNT_BIT_POSITION = 3 * 4 * 6;
    uint256 constant ALLOW_CLOSE_BIT_POSITION = 3 * 4 * 6 + 4 * 8;
    uint256 constant ALLOW_OPEN_BIT_POSITION = 3 * 4 * 6 + 4 * 8 + 4;
    uint256 constant DECIMALS_BIT_POSITION = 3 * 4 * 6 + 4 * 8 + 4 + 4;
    uint256 constant DECREASE_NUM_LIMIT_BIT_POSITION = 120;
    uint256 constant VALID_DECREASE_BIT_POSITION = 120 + 4;

    uint256 constant DENOMINATOR_SLIPPAGE = 10 ** 4; // 分母

    function setMinSlippage(
        IMarketValid.Props memory self,
        uint256 minSp
    ) internal pure {
        if (minSp > 16 ** 3) {
            revert("sp too big");
        }
        self.data = (self.data & MIN_SLIPPAGE_MASK) | minSp;
    }

    function getMinSlippage(
        IMarketValid.Props memory self
    ) internal pure returns (uint256) {
        return self.data & ~MIN_SLIPPAGE_MASK;
    }

    function setMaxSlippage(
        IMarketValid.Props memory self,
        uint256 minSp
    ) internal pure {
        if (minSp > 16 ** 3) {
            revert("ms too big");
        }
        self.data =
            (self.data & MAX_SLIPPAGE_MASK) |
            (minSp << MAX_SLIPPAGE_BIT_POSITION);
    }

    function getMaxSlippage(
        IMarketValid.Props memory self
    ) internal pure returns (uint256) {
        return (self.data & ~MAX_SLIPPAGE_MASK) >> MAX_SLIPPAGE_BIT_POSITION;
    }

    function setMinLev(
        // 已经检查
        IMarketValid.Props memory self,
        uint256 minSp
    ) internal pure {
        if (minSp > 16 ** 3) {
            revert("ml too big");
        }
        self.data =
            (self.data & MIN_LEV_MASK) |
            (minSp << MIN_LEV_BIT_POSITION);
    }

    function getMinLev(
        IMarketValid.Props memory self
    ) internal pure returns (uint256) {
        // return 2;
        return (self.data & ~MIN_LEV_MASK) >> MIN_LEV_BIT_POSITION;
    }

    function setMaxLev(
        // checked
        IMarketValid.Props memory self,
        uint256 minSp
    ) internal pure {
        if (minSp > 16 ** 3) {
            revert("ml too big");
        }
        self.data =
            (self.data & MAX_LEV_MASK) |
            (minSp << MAX_LEV_BIT_POSITION);
    }

    function getMaxLev(
        IMarketValid.Props memory self
    ) internal pure returns (uint256) {
        return (self.data & ~MAX_LEV_MASK) >> MAX_LEV_BIT_POSITION;
    }

    function setMinPay(
        //checked
        IMarketValid.Props memory self,
        uint256 minSp
    ) internal pure {
        if (minSp > 16 ** 3) {
            revert("mp too big");
        }

        self.data =
            (self.data & MIN_PAY_MASK) |
            (minSp << MIN_PAY_BIT_POSITION);
    }

    function getMinPay(
        IMarketValid.Props memory self
    ) internal pure returns (uint256) {
        return
            ((self.data & ~MIN_PAY_MASK) >> MIN_PAY_BIT_POSITION) *
            self.getDecimals();
    }

    function setMinCollateral(
        IMarketValid.Props memory self,
        uint256 minSp
    ) internal pure {
        if (minSp > 16 ** 3) {
            revert("mc too big");
        }
        self.data =
            (self.data & MIN_COL_MASK) |
            (minSp << MIN_COL_BIT_POSITION);
    }

    function getMinCollateral(
        IMarketValid.Props memory self
    ) internal pure returns (uint256) {
        return
            ((self.data & ~MIN_COL_MASK) >> MIN_COL_BIT_POSITION) *
            self.getDecimals();
    }

    function setDecrOrderLmt(
        IMarketValid.Props memory self,
        uint256 minSp
    ) internal pure {
        if (minSp > 16 ** 3) {
            revert("mc too big");
        }
        self.data =
            (self.data & DECREASE_NUM_LIMIT_MASK) |
            (minSp << DECREASE_NUM_LIMIT_BIT_POSITION);
    }

    function getDecrOrderLmt(
        IMarketValid.Props memory self
    ) internal pure returns (uint256 ret) {
        ret = ((self.data & ~DECREASE_NUM_LIMIT_MASK) >>
            DECREASE_NUM_LIMIT_BIT_POSITION);
        if (ret == 0) {
            ret = 10;
        }
    }

    function setMaxTradeAmount(
        IMarketValid.Props memory self,
        uint256 minSp
    ) internal pure {
        if (minSp > 16 ** 8) {
            revert("mta too big");
        }
        self.data =
            (self.data & MAX_TRADE_AMOUNT_MASK) |
            (minSp << MAX_TRADE_AMOUNT_BIT_POSITION);
    }

    function getMaxTradeAmount(
        IMarketValid.Props memory self
    ) internal pure returns (uint256) {
        return
            ((self.data & ~MAX_TRADE_AMOUNT_MASK) >>
                MAX_TRADE_AMOUNT_BIT_POSITION) * self.getDecimals();
    }

    function setAllowClose(
        IMarketValid.Props memory self,
        bool allow
    ) internal pure {
        // return;
        self.data =
            (self.data & ALLOW_CLOSE_MASK) |
            (uint256(allow ? 1 : 0) << ALLOW_CLOSE_BIT_POSITION);
    }

    function getEnableValidDecrease(
        IMarketValid.Props memory self
    ) internal pure returns (bool) {
        return (self.data & ~VALID_DECREASE_MASK) != 0;
    }

    function setEnableValidDecrease(
        IMarketValid.Props memory self,
        bool allow
    ) internal pure {
        self.data =
            (self.data & VALID_DECREASE_MASK) |
            (uint256(allow ? 1 : 0) << VALID_DECREASE_BIT_POSITION);
    }

    function getAllowClose(
        IMarketValid.Props memory self
    ) internal pure returns (bool) {
        // return true;
        return (self.data & ~ALLOW_CLOSE_MASK) != 0;
    }

    function setAllowOpen(
        IMarketValid.Props memory self,
        bool allow
    ) internal pure {
        // return;
        self.data =
            (self.data & ALLOW_OPEN_MASK) |
            (uint256(allow ? 1 : 0) << ALLOW_OPEN_BIT_POSITION);
    }

    function getAllowOpen(
        IMarketValid.Props memory self
    ) internal pure returns (bool) {
        // return true;
        return (self.data & ~ALLOW_OPEN_MASK) != 0;
    }

    function setDecimals(
        IMarketValid.Props memory self,
        uint256 _decimals
    ) internal pure {
        self.data =
            (self.data & DECIMALS_MASK) |
            (_decimals << DECIMALS_BIT_POSITION);
    }

    function getDecimals(
        IMarketValid.Props memory self
    ) internal pure returns (uint256) {
        return 10 ** ((self.data & ~DECIMALS_MASK) >> DECIMALS_BIT_POSITION);
    }
}

