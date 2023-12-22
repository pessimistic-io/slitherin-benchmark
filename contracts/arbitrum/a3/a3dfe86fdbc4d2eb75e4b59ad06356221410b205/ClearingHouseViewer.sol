// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { IERC20 } from "./IERC20.sol";
import { Decimal } from "./Decimal.sol";
import { SignedDecimal } from "./SignedDecimal.sol";
import { MixedDecimal } from "./MixedDecimal.sol";
import { IAmm } from "./IAmm.sol";
import { IInsuranceFund } from "./IInsuranceFund.sol";
import { ClearingHouse } from "./ClearingHouse.sol";

contract ClearingHouseViewer {
    using Decimal for Decimal.decimal;
    using SignedDecimal for SignedDecimal.signedDecimal;
    using MixedDecimal for SignedDecimal.signedDecimal;

    ClearingHouse public clearingHouse;

    //
    // FUNCTIONS
    //

    constructor(ClearingHouse _clearingHouse) {
        clearingHouse = _clearingHouse;
    }

    //
    // Public
    //

    /**
     * @notice get unrealized PnL
     * @param _amm IAmm address
     * @param _trader trader address
     * @param _pnlCalcOption ClearingHouse.PnlCalcOption, can be SPOT_PRICE or TWAP.
     * @return unrealized PnL in 18 digits
     */
    function getUnrealizedPnl(
        IAmm _amm,
        address _trader,
        ClearingHouse.PnlCalcOption _pnlCalcOption
    ) external view returns (SignedDecimal.signedDecimal memory) {
        (, SignedDecimal.signedDecimal memory unrealizedPnl) = (
            clearingHouse.getPositionNotionalAndUnrealizedPnl(_amm, _trader, _pnlCalcOption)
        );
        return unrealizedPnl;
    }

    /**
     * @notice get personal balance with funding payment
     * @param _quoteToken ERC20 token address
     * @param _trader trader address
     * @return margin personal balance with funding payment in 18 digits
     */
    function getPersonalBalanceWithFundingPayment(IERC20 _quoteToken, address _trader)
        external
        view
        returns (Decimal.decimal memory margin)
    {
        IInsuranceFund insuranceFund = clearingHouse.insuranceFund();
        IAmm[] memory amms = insuranceFund.getAllAmms();
        for (uint256 i = 0; i < amms.length; i++) {
            if (IAmm(amms[i]).quoteAsset() != _quoteToken) {
                continue;
            }
            Decimal.decimal memory posMargin = getPersonalPositionWithFundingPayment(
                amms[i],
                _trader
            ).margin;
            margin = margin.addD(posMargin);
        }
    }

    /**
     * @notice get personal position with funding payment
     * @param _amm IAmm address
     * @param _trader trader address
     * @return position ClearingHouse.Position struct
     */
    function getPersonalPositionWithFundingPayment(IAmm _amm, address _trader)
        public
        view
        returns (ClearingHouse.Position memory position)
    {
        position = clearingHouse.getPosition(_amm, _trader);
        SignedDecimal.signedDecimal memory marginWithFundingPayment = MixedDecimal
            .fromDecimal(position.margin)
            .addD(
                getFundingPayment(position, clearingHouse.getLatestCumulativePremiumFraction(_amm))
            );
        position.margin = marginWithFundingPayment.toInt() >= 0
            ? marginWithFundingPayment.abs()
            : Decimal.zero();
    }

    /**
     * @notice get personal margin ratio
     * @param _amm IAmm address
     * @param _trader trader address
     * @return personal margin ratio in 18 digits
     */
    function getMarginRatio(IAmm _amm, address _trader)
        external
        view
        returns (SignedDecimal.signedDecimal memory)
    {
        return clearingHouse.getMarginRatio(_amm, _trader);
    }

    /**
     * @notice get withdrawable margin
     * @param _amm IAmm address
     * @param _trader trader address
     * @return withdrawable margin in 18 digits
     */
    function getFreeCollateral(IAmm _amm, address _trader)
        external
        view
        returns (SignedDecimal.signedDecimal memory)
    {
        // get trader's margin
        ClearingHouse.Position memory position = getPersonalPositionWithFundingPayment(
            _amm,
            _trader
        );

        // get trader's unrealized PnL and choose the least beneficial one for the trader
        (
            Decimal.decimal memory spotPositionNotional,
            SignedDecimal.signedDecimal memory spotPricePnl
        ) = (
                clearingHouse.getPositionNotionalAndUnrealizedPnl(
                    _amm,
                    _trader,
                    ClearingHouse.PnlCalcOption.SPOT_PRICE
                )
            );
        (
            Decimal.decimal memory twapPositionNotional,
            SignedDecimal.signedDecimal memory twapPricePnl
        ) = (
                clearingHouse.getPositionNotionalAndUnrealizedPnl(
                    _amm,
                    _trader,
                    ClearingHouse.PnlCalcOption.TWAP
                )
            );

        SignedDecimal.signedDecimal memory unrealizedPnl;
        Decimal.decimal memory positionNotional;
        (unrealizedPnl, positionNotional) = (spotPricePnl.toInt() > twapPricePnl.toInt())
            ? (twapPricePnl, twapPositionNotional)
            : (spotPricePnl, spotPositionNotional);

        // min(margin + funding, margin + funding + unrealized PnL) - position value * initMarginRatio
        SignedDecimal.signedDecimal memory accountValue = unrealizedPnl.addD(position.margin);
        SignedDecimal.signedDecimal memory minCollateral = accountValue
            .subD(position.margin)
            .toInt() > 0
            ? MixedDecimal.fromDecimal(position.margin)
            : accountValue;

        Decimal.decimal memory initMarginRatio = _amm.getRatios().initMarginRatio;
        SignedDecimal.signedDecimal memory marginRequirement = position.size.toInt() > 0
            ? MixedDecimal.fromDecimal(position.openNotional).mulD(initMarginRatio)
            : MixedDecimal.fromDecimal(positionNotional).mulD(initMarginRatio);

        return minCollateral.subD(marginRequirement);
    }

    //
    // PRIVATE
    //

    // negative means trader paid and vice versa
    function getFundingPayment(
        ClearingHouse.Position memory _position,
        SignedDecimal.signedDecimal memory _latestCumulativePremiumFraction
    ) private pure returns (SignedDecimal.signedDecimal memory) {
        return
            _position.size.toInt() == 0
                ? SignedDecimal.zero()
                : _latestCumulativePremiumFraction
                    .subD(_position.lastUpdatedCumulativePremiumFraction)
                    .mulD(_position.size)
                    .mulScalar(-1);
    }
}

