// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IOracle.sol";
import "./IFeeCalculator.sol";
import "./IFundingManager.sol";

library PerpLib {
    uint256 private constant BASE = 10**8;
    uint256 private constant FUNDING_BASE = 10**12;

    function _canTakeProfit(
        bool isLong,
        uint256 positionTimestamp,
        uint256 positionOraclePrice,
        uint256 oraclePrice,
        uint256 minPriceChange,
        uint256 minProfitTime
    ) internal view returns(bool) {
        if (block.timestamp > positionTimestamp + minProfitTime) {
            return true;
        } else if (isLong && oraclePrice > positionOraclePrice * (10**4 + minPriceChange) / (10**4)) {
            return true;
        } else if (!isLong && oraclePrice < positionOraclePrice * (10**4 - minPriceChange) / (10**4)) {
            return true;
        }
        return false;
    }

    function _getPnl(
        bool isLong,
        uint256 positionPrice,
        uint256 positionLeverage,
        uint256 margin,
        uint256 price
    ) internal view returns(int256 _pnl) {
        bool pnlIsNegative;
        uint256 pnl;
        if (isLong) {
            if (price >= positionPrice) {
                pnl = margin * positionLeverage * (price - positionPrice) / positionPrice / BASE;
            } else {
                pnl = margin * positionLeverage * (positionPrice - price) / positionPrice / BASE;
                pnlIsNegative = true;
            }
        } else {
            if (price > positionPrice) {
                pnl = margin * positionLeverage * (price - positionPrice) / positionPrice / BASE;
                pnlIsNegative = true;
            } else {
                pnl = margin * positionLeverage * (positionPrice - price) / positionPrice / BASE;
            }
        }

        if (pnlIsNegative) {
            _pnl = -1 * int256(pnl);
        } else {
            _pnl = int256(pnl);
        }

        return _pnl;
    }

    function _getFundingPayment(
        address fundingManager,
        bool isLong,
        uint256 productId,
        uint256 positionLeverage,
        uint256 margin,
        int256 funding
    ) internal view returns(int256) {
        return isLong ? int256(margin * positionLeverage) * (IFundingManager(fundingManager).getFunding(productId) - funding) / int256(BASE * FUNDING_BASE) :
            int256(margin * positionLeverage) * (funding - IFundingManager(fundingManager).getFunding(productId)) / int256(BASE * FUNDING_BASE);
    }

    function _getTradeFee(
        uint256 margin,
        uint256 leverage,
        uint256 productFee,
        address productToken,
        address user,
        address sender,
        address feeCalculator
    ) internal view returns(uint256) {
        uint256 fee = IFeeCalculator(feeCalculator).getFee(productToken, productFee, user, sender);
        return margin * leverage / BASE * fee / 10**4;
    }
}

