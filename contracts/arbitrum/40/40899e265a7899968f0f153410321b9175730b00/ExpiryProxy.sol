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
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

import { IDolomiteMargin } from "./IDolomiteMargin.sol";
import { Account } from "./Account.sol";
import { Actions } from "./Actions.sol";
import { Decimal } from "./Decimal.sol";
import { Interest } from "./Interest.sol";
import { DolomiteMarginMath } from "./DolomiteMarginMath.sol";
import { Monetary } from "./Monetary.sol";
import { Require } from "./Require.sol";
import { Types } from "./Types.sol";

import { IExpiry } from "./IExpiry.sol";

import { HasLiquidatorRegistry } from "./HasLiquidatorRegistry.sol";
import { LiquidatorProxyBase } from "./LiquidatorProxyBase.sol";
import { OnlyDolomiteMargin } from "./OnlyDolomiteMargin.sol";

import { AccountActionLib } from "./AccountActionLib.sol";


/**
 * @title ExpiryProxy
 * @author Dolomite
 *
 * Contract for expiring other accounts in DolomiteMargin.
 */
contract ExpiryProxy is HasLiquidatorRegistry, OnlyDolomiteMargin, ReentrancyGuard {
    using SafeMath for uint256;

    // ============ Constants =============

    bytes32 private FILE = "ExpiryProxy";

    // ============== Storage ==============

    IExpiry public EXPIRY;

    // ============ Constructor ============

    constructor (
        address _liquidatorAssetRegistry,
        address _expiry,
        address _dolomiteMargin
    )
    public
    HasLiquidatorRegistry(_liquidatorAssetRegistry)
    OnlyDolomiteMargin(_dolomiteMargin)
    {
        EXPIRY = IExpiry(_expiry);
    }

    function expire(
        Account.Info memory _solidAccount,
        Account.Info memory _liquidAccount,
        uint256 _owedMarket,
        uint256 _heldMarket,
        uint32 _expirationTimestamp
    )
        public
        requireIsAssetWhitelistedForLiquidation(_owedMarket)
        requireIsAssetWhitelistedForLiquidation(_heldMarket)
        nonReentrant
    {
        Require.that(
            _solidAccount.owner == msg.sender || DOLOMITE_MARGIN.getIsLocalOperator(_solidAccount.owner, msg.sender),
            FILE,
            "Sender not operator",
            msg.sender
        );
        Require.that(
            _expirationTimestamp == EXPIRY.getExpiry(_liquidAccount, _owedMarket),
            FILE,
            "Invalid expiration timestamp"
        );

        // Expire the account
        Account.Info[] memory accounts = new Account.Info[](2);
        accounts[0] = _solidAccount;
        accounts[1] = _liquidAccount;

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        (uint256 solidHeldUpdateWithReward, uint256 owedWeiToLiquidate, bool flipMarkets) = _getAmountsForExpiration(
            _liquidAccount,
            _owedMarket,
            _heldMarket,
            _expirationTimestamp
        );
        actions[0] = AccountActionLib.encodeExpiryLiquidateAction(
            /* _solidAccountId = */ 0,
            /* _liquidAccountId = */ 1,
            _owedMarket,
            _heldMarket,
            address(EXPIRY),
            _expirationTimestamp,
            solidHeldUpdateWithReward,
            owedWeiToLiquidate,
            flipMarkets
        );

        DOLOMITE_MARGIN.operate(accounts, actions);
    }

    function _getAmountsForExpiration(
        Account.Info memory _liquidAccount,
        uint256 _owedMarket,
        uint256 _heldMarket,
        uint32 _expirationTimestamp
    ) internal view returns (uint256 solidHeldUpdateWithReward, uint256 owedWeiToLiquidate, bool flipMarkets) {
        uint256 liquidHeldWei = DOLOMITE_MARGIN.getAccountWei(_liquidAccount, _heldMarket).value;
        uint256 liquidOwedWei = DOLOMITE_MARGIN.getAccountWei(_liquidAccount, _owedMarket).value;

        uint256 heldPrice = DOLOMITE_MARGIN.getMarketPrice(_heldMarket).value;
        uint256 owedPrice = DOLOMITE_MARGIN.getMarketPrice(_owedMarket).value;
        (, Monetary.Price memory owedPriceAdj) = EXPIRY.getSpreadAdjustedPrices(
            _heldMarket,
            _owedMarket,
            _expirationTimestamp
        );

        if (liquidHeldWei.mul(heldPrice) < liquidOwedWei.mul(owedPrice)) {
            // The held collateral is worth less than the adjusted debt
            solidHeldUpdateWithReward = liquidHeldWei;
            owedWeiToLiquidate = DolomiteMarginMath.getPartialRoundUp(
                liquidHeldWei,
                heldPrice,
                owedPriceAdj.value
            );
            flipMarkets = true;
        } else {
            solidHeldUpdateWithReward = DolomiteMarginMath.getPartial(
                liquidOwedWei,
                owedPriceAdj.value,
                heldPrice
            );
            owedWeiToLiquidate = liquidOwedWei;
            flipMarkets = false;
        }
    }

    function _getAccountValue(
        Account.Info memory _account,
        uint256 _market
    ) internal view returns (uint256) {
        uint256 price = DOLOMITE_MARGIN.getMarketPrice(_market).value;
        uint256 heldAmount = DOLOMITE_MARGIN.getAccountWei(_account, _market).value;
        return price.mul(heldAmount);
    }
}

