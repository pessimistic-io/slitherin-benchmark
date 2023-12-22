/*

    Copyright 2019 dYdX Trading Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

*/

pragma solidity ^0.5.7;
pragma experimental ABIEncoderV2;

import { SafeMath } from "./SafeMath.sol";

import { IDolomiteMargin } from "./IDolomiteMargin.sol";
import { IExpiry } from "./IExpiry.sol";

import { Account } from "./Account.sol";
import { Bits } from "./Bits.sol";
import { Decimal } from "./Decimal.sol";
import { DolomiteMarginMath } from "./DolomiteMarginMath.sol";
import { Interest } from "./Interest.sol";
import { Monetary } from "./Monetary.sol";
import { Require } from "./Require.sol";
import { Time } from "./Time.sol";
import { Types } from "./Types.sol";


/**
 * @title LiquidatorProxyHelper
 * @author Dolomite
 *
 * Inheritable contract that allows sharing code across different liquidator proxy contracts
 */
contract LiquidatorProxyHelper {
    using SafeMath for uint;
    using Types for Types.Par;

    // ============ Constants ============

    bytes32 private constant FILE = "LiquidatorProxyHelper";
    uint256 private constant MAX_UINT_BITS = 256;
    uint256 private constant ONE = 1;

    // ============ Structs ============

    struct MarketInfo {
        uint256 marketId;
        Decimal.D256 spreadPremium;
        Monetary.Price price;
        Interest.Index index;
    }

    // ============ Structs ============

    struct Constants {
        IDolomiteMargin dolomiteMargin;
        Account.Info solidAccount;
        Account.Info liquidAccount;
        MarketInfo[] markets;
        uint256[] liquidMarkets;
        IExpiry expiryProxy;
        uint32 expiry;
    }

    struct LiquidatorProxyCache {
        // mutable
        uint256 owedWeiToLiquidate;
        // The amount of heldMarket the solidAccount will receive. Includes the liquidation reward. Useful as the
        // `amountIn` for a trade
        uint256 solidHeldUpdateWithReward;
        Types.Wei solidHeldWei;
        Types.Wei solidOwedWei;
        Types.Wei liquidHeldWei;
        Types.Wei liquidOwedWei;

        // immutable
        Decimal.D256 spread;
        uint256 heldMarket;
        uint256 owedMarket;
        uint256 heldPrice;
        uint256 owedPrice;
        uint256 owedPriceAdj;
        bool flipMarkets;
    }

    // ============ Internal Functions ============

    /**
     * Pre-populates cache values for some pair of markets.
     */
    function _initializeCache(
        Constants memory _constants,
        uint256 _heldMarket,
        uint256 _owedMarket
    )
    internal
    view
    returns (LiquidatorProxyCache memory)
    {
        MarketInfo memory heldMarketInfo = _binarySearch(_constants.markets, _heldMarket);
        MarketInfo memory owedMarketInfo = _binarySearch(_constants.markets, _owedMarket);

        Decimal.D256 memory spread = _constants.dolomiteMargin.getLiquidationSpreadForPair(_heldMarket, _owedMarket);
        uint256 owedPriceAdj;
        if (_constants.expiry > 0) {
            (, Monetary.Price memory owedPricePrice) = _constants.expiryProxy.getSpreadAdjustedPrices(
                _heldMarket,
                _owedMarket,
                _constants.expiry
            );
            owedPriceAdj = owedPricePrice.value;
        } else {
            owedPriceAdj = Decimal.mul(owedMarketInfo.price.value, Decimal.onePlus(spread));
        }

        return LiquidatorProxyCache({
            owedWeiToLiquidate: 0,
            solidHeldUpdateWithReward: 0,
            solidHeldWei: Interest.parToWei(
                _constants.dolomiteMargin.getAccountPar(_constants.solidAccount, _heldMarket),
                heldMarketInfo.index
            ),
            solidOwedWei: Interest.parToWei(
                _constants.dolomiteMargin.getAccountPar(_constants.solidAccount, _owedMarket),
                owedMarketInfo.index
            ),
            liquidHeldWei: Interest.parToWei(
                _constants.dolomiteMargin.getAccountPar(_constants.liquidAccount, _heldMarket),
                heldMarketInfo.index
            ),
            liquidOwedWei: Interest.parToWei(
                _constants.dolomiteMargin.getAccountPar(_constants.liquidAccount, _owedMarket),
                owedMarketInfo.index
            ),
            spread: spread,
            heldMarket: _heldMarket,
            owedMarket: _owedMarket,
            heldPrice: heldMarketInfo.price.value,
            owedPrice: owedMarketInfo.price.value,
            owedPriceAdj: owedPriceAdj,
            flipMarkets: false
        });
    }

    /**
     * Make some basic checks before attempting to liquidate an account.
     *  - Require that the msg.sender has the permission to use the liquidator account
     *  - Require that the liquid account is liquidatable based on the accounts global value (all assets held and owed,
     *    not just what's being liquidated)
     */
    function _checkConstants(
        Constants memory _constants,
        Account.Info memory _liquidAccount,
        uint256 _owedMarket,
        uint256 _heldMarket,
        uint256 _expiry
    )
    internal
    view
    {
        assert(address(_constants.dolomiteMargin) != address(0));
        Require.that(
            _owedMarket != _heldMarket,
            FILE,
            "owedMarket equals heldMarket",
            _owedMarket
        );

        Require.that(
            !_constants.dolomiteMargin.getAccountPar(_liquidAccount, _owedMarket).isPositive(),
            FILE,
            "owed market cannot be positive",
            _owedMarket
        );

        Require.that(
            _constants.dolomiteMargin.getAccountPar(_liquidAccount, _heldMarket).isPositive(),
            FILE,
            "held market cannot be negative",
            _heldMarket
        );

        Require.that(
            uint32(_expiry) == _expiry,
            FILE,
            "expiry overflow",
            _expiry
        );
    }

    /**
     * Make some basic checks before attempting to liquidate an account.
     *  - Require that the msg.sender has the permission to use the liquidator account
     *  - Require that the liquid account is liquidatable based on the accounts global value (all assets held and owed,
     *    not just what's being liquidated)
     */
    function _checkBasicRequirements(
        Constants memory _constants,
        uint256 _owedMarket
    )
    internal
    view
    {
        // check credentials for msg.sender
        Require.that(
            _constants.solidAccount.owner == msg.sender
            || _constants.dolomiteMargin.getIsLocalOperator(_constants.solidAccount.owner, msg.sender),
            FILE,
            "Sender not operator",
            msg.sender
        );

        if (_constants.expiry == 0) {
            // user is getting liquidated, not expired. Check liquid account is indeed under-collateralized
            (
                Monetary.Value memory liquidSupplyValue,
                Monetary.Value memory liquidBorrowValue
            ) = _getAdjustedAccountValues(
                _constants.dolomiteMargin,
                _constants.markets,
                _constants.liquidAccount,
                _constants.liquidMarkets
            );
            Require.that(
                _constants.dolomiteMargin.getAccountStatus(_constants.liquidAccount) == Account.Status.Liquid
                || !_isCollateralized(
                    liquidSupplyValue.value,
                    liquidBorrowValue.value,
                    _constants.dolomiteMargin.getMarginRatio()
                ),
                FILE,
                "Liquid account not liquidatable",
                _constants.liquidAccount.owner,
                _constants.liquidAccount.number
            );
        } else {
            // check the expiration is valid; to get here we already know constants.expiry != 0
            uint32 expiry = _constants.expiryProxy.getExpiry(_constants.liquidAccount, _owedMarket);
            Require.that(
                expiry == _constants.expiry,
                FILE,
                "Expiry mismatch",
                expiry,
                _constants.expiry
            );
            Require.that(
                expiry <= Time.currentTime(),
                FILE,
                "Borrow not yet expired",
                expiry
            );
        }
    }

    /**
     * Calculate the additional owedAmount that can be liquidated until the collateralization of the liquidator account
     * reaches the minLiquidatorRatio. By this point, the cache will be set such that the amount of owedMarket is
     * non-positive and the amount of heldMarket is non-negative.
     */
    function _calculateAndSetMaxLiquidationAmount(
        LiquidatorProxyCache memory _cache
    )
    internal
    pure
    {
        uint256 liquidHeldValue = _cache.heldPrice.mul(_cache.liquidHeldWei.value);
        uint256 liquidOwedValue = _cache.owedPriceAdj.mul(_cache.liquidOwedWei.value);
        if (liquidHeldValue < liquidOwedValue) {
            // The held collateral is worth less than the debt
            _cache.solidHeldUpdateWithReward = _cache.liquidHeldWei.value;
            _cache.owedWeiToLiquidate = DolomiteMarginMath.getPartialRoundUp(
                _cache.liquidHeldWei.value,
                _cache.heldPrice,
                _cache.owedPriceAdj
            );
            _cache.flipMarkets = true;
        } else {
            _cache.solidHeldUpdateWithReward = DolomiteMarginMath.getPartial(
                _cache.liquidOwedWei.value,
                _cache.owedPriceAdj,
                _cache.heldPrice
            );
            _cache.owedWeiToLiquidate = _cache.liquidOwedWei.value;
        }
    }

    /**
     * Returns true if the supplyValue over-collateralizes the borrowValue by the ratio.
     */
    function _isCollateralized(
        uint256 supplyValue,
        uint256 borrowValue,
        Decimal.D256 memory ratio
    )
    internal
    pure
    returns (bool)
    {
        uint256 requiredMargin = Decimal.mul(borrowValue, ratio);
        return supplyValue >= borrowValue.add(requiredMargin);
    }

    /**
     * Gets the current total supplyValue and borrowValue for some account. Takes into account what
     * the current index will be once updated.
     */
    function _getAccountValues(
        IDolomiteMargin dolomiteMargin,
        MarketInfo[] memory marketInfos,
        Account.Info memory account,
        uint256[] memory marketIds
    )
    internal
    view
    returns (
        Monetary.Value memory,
        Monetary.Value memory
    )
    {
        return _getAccountValues(
            dolomiteMargin,
            marketInfos,
            account,
            marketIds,
            /* adjustForSpreadPremiums = */ false // solium-disable-line indentation
        );
    }

    /**
     * Gets the adjusted current total supplyValue and borrowValue for some account. Takes into account what
     * the current index will be once updated and the spread premium.
     */
    function _getAdjustedAccountValues(
        IDolomiteMargin dolomiteMargin,
        MarketInfo[] memory marketInfos,
        Account.Info memory account,
        uint256[] memory marketIds
    )
    internal
    view
    returns (
        Monetary.Value memory,
        Monetary.Value memory
    )
    {
        return _getAccountValues(
            dolomiteMargin,
            marketInfos,
            account,
            marketIds,
            /* adjustForSpreadPremiums = */ true // solium-disable-line indentation
        );
    }

    function _getMarketInfos(
        IDolomiteMargin dolomiteMargin,
        uint256[] memory solidMarkets,
        uint256[] memory liquidMarkets
    ) internal view returns (MarketInfo[] memory) {
        uint[] memory marketBitmaps = Bits.createBitmaps(dolomiteMargin.getNumMarkets());
        uint marketsLength = 0;
        marketsLength = _addMarketsToBitmap(solidMarkets, marketBitmaps, marketsLength);
        marketsLength = _addMarketsToBitmap(liquidMarkets, marketBitmaps, marketsLength);

        uint counter = 0;
        MarketInfo[] memory marketInfos = new MarketInfo[](marketsLength);
        for (uint i = 0; i < marketBitmaps.length; i++) {
            uint bitmap = marketBitmaps[i];
            while (bitmap != 0) {
                uint nextSetBit = Bits.getLeastSignificantBit(bitmap);
                uint marketId = Bits.getMarketIdFromBit(i, nextSetBit);

                marketInfos[counter++] = MarketInfo({
                    marketId: marketId,
                    spreadPremium: dolomiteMargin.getMarketSpreadPremium(marketId),
                    price: dolomiteMargin.getMarketPrice(marketId),
                    index: dolomiteMargin.getMarketCurrentIndex(marketId)
                });

                // unset the set bit
                bitmap = Bits.unsetBit(bitmap, nextSetBit);
            }
            if (counter == marketsLength) {
                break;
            }
        }

        return marketInfos;
    }

    function _binarySearch(
        MarketInfo[] memory markets,
        uint marketId
    ) internal pure returns (MarketInfo memory) {
        return _binarySearch(
            markets,
            0,
            markets.length,
            marketId
        );
    }

    // ============ Private Functions ============

    function _getAccountValues(
        IDolomiteMargin dolomiteMargin,
        MarketInfo[] memory marketInfos,
        Account.Info memory account,
        uint256[] memory marketIds,
        bool adjustForSpreadPremiums
    )
    private
    view
    returns (
        Monetary.Value memory,
        Monetary.Value memory
    )
    {
        Monetary.Value memory supplyValue;
        Monetary.Value memory borrowValue;

        for (uint256 i = 0; i < marketIds.length; i++) {
            Types.Par memory par = dolomiteMargin.getAccountPar(account, marketIds[i]);
            MarketInfo memory marketInfo = _binarySearch(marketInfos, marketIds[i]);
            Types.Wei memory userWei = Interest.parToWei(par, marketInfo.index);
            uint256 assetValue = userWei.value.mul(marketInfo.price.value);
            Decimal.D256 memory spreadPremium = Decimal.one();
            if (adjustForSpreadPremiums) {
                spreadPremium = Decimal.onePlus(marketInfo.spreadPremium);
            }
            if (userWei.sign) {
                supplyValue.value = supplyValue.value.add(Decimal.div(assetValue, spreadPremium));
            } else {
                borrowValue.value = borrowValue.value.add(Decimal.mul(assetValue, spreadPremium));
            }
        }

        return (supplyValue, borrowValue);
    }

    // solium-disable-next-line security/no-assign-params
    function _addMarketsToBitmap(
        uint256[] memory markets,
        uint256[] memory bitmaps,
        uint marketsLength
    ) private pure returns (uint) {
        for (uint i = 0; i < markets.length; i++) {
            if (!Bits.hasBit(bitmaps, markets[i])) {
                Bits.setBit(bitmaps, markets[i]);
                marketsLength += 1;
            }
        }
        return marketsLength;
    }

    function _binarySearch(
        MarketInfo[] memory markets,
        uint beginInclusive,
        uint endExclusive,
        uint marketId
    ) private pure returns (MarketInfo memory) {
        uint len = endExclusive - beginInclusive;
        if (len == 0 || (len == 1 && markets[beginInclusive].marketId != marketId)) {
            revert("LiquidatorProxyHelper: market not found");
        }

        uint mid = beginInclusive + len / 2;
        uint midMarketId = markets[mid].marketId;
        if (marketId < midMarketId) {
            return _binarySearch(
                markets,
                beginInclusive,
                mid,
                marketId
            );
        } else if (marketId > midMarketId) {
            return _binarySearch(
                markets,
                mid + 1,
                endExclusive,
                marketId
            );
        } else {
            return markets[mid];
        }
    }

}

