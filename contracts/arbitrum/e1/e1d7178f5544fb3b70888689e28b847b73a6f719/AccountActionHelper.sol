/*

    Copyright 2022 Dolomite.

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

import { IDolomiteMargin } from "./IDolomiteMargin.sol";

import { Account } from "./Account.sol";
import { Actions } from "./Actions.sol";
import { Require } from "./Require.sol";
import { Types } from "./Types.sol";

import { IExpiry } from "./IExpiry.sol";

import { AccountBalanceHelper } from "./AccountBalanceHelper.sol";


/**
 * @title AccountActionHelper
 * @author Dolomite
 *
 * Library contract that makes specific actions easy to call
 */
library AccountActionHelper {

    // ============ Constants ============

    bytes32 constant FILE = "AccountActionHelper";

    uint256 constant ALL = uint256(-1);

    // ============ Functions ============

    function all() internal pure returns (uint256) {
        return ALL;
    }

    function deposit(
        IDolomiteMargin _dolomiteMargin,
        address _accountOwner,
        address _fromAccount,
        uint256 _toAccountNumber,
        uint256 _marketId,
        Types.AssetAmount memory _amount
    ) internal {
        Account.Info[] memory accounts = new Account.Info[](1);
        accounts[0] = Account.Info({
            owner: _accountOwner,
            number: _toAccountNumber
        });

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        actions[0] = Actions.ActionArgs({
            actionType: Actions.ActionType.Deposit,
            accountId: 0,
            amount: _amount,
            primaryMarketId: _marketId,
            secondaryMarketId: 0,
            otherAddress: _fromAccount,
            otherAccountId: 0,
            data: bytes("")
        });

        _dolomiteMargin.operate(accounts, actions);
    }

    /**
     *  Withdraws `_marketId` from `_fromAccount` to `_toAccount`
     */
    function withdraw(
        IDolomiteMargin _dolomiteMargin,
        address _accountOwner,
        uint256 _fromAccountNumber,
        address _toAccount,
        uint256 _marketId,
        Types.AssetAmount memory _amount,
        AccountBalanceHelper.BalanceCheckFlag _balanceCheckFlag
    ) internal {
        Account.Info[] memory accounts = new Account.Info[](1);
        accounts[0] = Account.Info({
            owner: _accountOwner,
            number: _fromAccountNumber
        });

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        actions[0] = Actions.ActionArgs({
            actionType: Actions.ActionType.Withdraw,
            accountId: 0,
            amount: _amount,
            primaryMarketId: _marketId,
            secondaryMarketId: 0,
            otherAddress: _toAccount,
            otherAccountId: 0,
            data: bytes("")
        });

        _dolomiteMargin.operate(accounts, actions);

        if (
            _balanceCheckFlag == AccountBalanceHelper.BalanceCheckFlag.Both
            || _balanceCheckFlag == AccountBalanceHelper.BalanceCheckFlag.From
        ) {
            AccountBalanceHelper.verifyBalanceIsNonNegative(
                _dolomiteMargin,
                accounts[0].owner,
                _fromAccountNumber,
                _marketId
            );
        }
    }

    /**
     * Transfers `_marketId` from `_fromAccount` to `_toAccount`
     */
    function transfer(
        IDolomiteMargin _dolomiteMargin,
        address _accountOwner,
        uint256 _fromAccountNumber,
        uint256 _toAccountNumber,
        uint256 _marketId,
        Types.AssetAmount memory _amount,
        AccountBalanceHelper.BalanceCheckFlag _balanceCheckFlag
    ) internal {
        Account.Info[] memory accounts = new Account.Info[](2);
        accounts[0] = Account.Info({
            owner: _accountOwner,
            number: _fromAccountNumber
        });
        accounts[1] = Account.Info({
            owner: _accountOwner,
            number: _toAccountNumber
        });

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        actions[0] = Actions.ActionArgs({
            actionType: Actions.ActionType.Transfer,
            accountId: 0,
            amount: _amount,
            primaryMarketId: _marketId,
            secondaryMarketId: 0,
            otherAddress: address(0),
            otherAccountId: 1,
            data: bytes("")
        });

        _dolomiteMargin.operate(accounts, actions);

        if (
            _balanceCheckFlag == AccountBalanceHelper.BalanceCheckFlag.Both
            || _balanceCheckFlag == AccountBalanceHelper.BalanceCheckFlag.From
        ) {
            AccountBalanceHelper.verifyBalanceIsNonNegative(
                _dolomiteMargin,
                _accountOwner,
                _fromAccountNumber,
                _marketId
            );
        }

        if (
            _balanceCheckFlag == AccountBalanceHelper.BalanceCheckFlag.Both
            || _balanceCheckFlag == AccountBalanceHelper.BalanceCheckFlag.To
        ) {
            AccountBalanceHelper.verifyBalanceIsNonNegative(
                _dolomiteMargin,
                _accountOwner,
                _toAccountNumber,
                _marketId
            );
        }
    }

    function encodeExpirationAction(
        Account.Info memory _account,
        uint256 _accountId,
        uint256 _owedMarketId,
        address _expiry,
        uint256 _expiryTimeDelta
    ) internal pure returns (Actions.ActionArgs memory) {
        Require.that(
            _expiryTimeDelta == uint32(_expiryTimeDelta),
            FILE,
            "invalid expiry time"
        );

        IExpiry.SetExpiryArg[] memory expiryArgs = new IExpiry.SetExpiryArg[](1);
        expiryArgs[0] = IExpiry.SetExpiryArg({
            account : _account,
            marketId : _owedMarketId,
            timeDelta : uint32(_expiryTimeDelta),
            forceUpdate : true
        });

        return Actions.ActionArgs({
            actionType : Actions.ActionType.Call,
            accountId : _accountId,
            // solium-disable-next-line arg-overflow
            amount : Types.AssetAmount(true, Types.AssetDenomination.Wei, Types.AssetReference.Delta, 0),
            primaryMarketId : 0,
            secondaryMarketId : 0,
            otherAddress : _expiry,
            otherAccountId : 0,
            data : abi.encode(IExpiry.CallFunctionType.SetExpiry, expiryArgs)
        });
    }

    function encodeExpiryLiquidateAction(
        uint256 _solidAccountId,
        uint256 _liquidAccountId,
        uint256 _owedMarketId,
        uint256 _heldMarketId,
        address _expiryProxy,
        uint32 _expiry,
        bool _flipMarkets
    ) internal pure returns (Actions.ActionArgs memory) {
        return Actions.ActionArgs({
        actionType: Actions.ActionType.Trade,
            accountId: _solidAccountId,
            amount: Types.AssetAmount({
                sign: true,
                denomination: Types.AssetDenomination.Wei,
                ref: Types.AssetReference.Target,
                value: 0
            }),
            primaryMarketId: !_flipMarkets ? _owedMarketId : _heldMarketId,
            secondaryMarketId: !_flipMarkets ? _heldMarketId : _owedMarketId,
            otherAddress: _expiryProxy,
            otherAccountId: _liquidAccountId,
            data: abi.encode(_owedMarketId, _expiry)
        });
    }

    function encodeLiquidateAction(
        uint256 _solidAccountId,
        uint256 _liquidAccountId,
        uint256 _owedMarketId,
        uint256 _heldMarketId,
        uint256 _owedWeiToLiquidate
    ) internal pure returns (Actions.ActionArgs memory) {
        return Actions.ActionArgs({
            actionType: Actions.ActionType.Liquidate,
            accountId: _solidAccountId,
            amount: Types.AssetAmount({
                sign: true,
                denomination: Types.AssetDenomination.Wei,
                ref: Types.AssetReference.Delta,
                value: _owedWeiToLiquidate
            }),
            primaryMarketId: _owedMarketId,
            secondaryMarketId: _heldMarketId,
            otherAddress: address(0),
            otherAccountId: _liquidAccountId,
            data: new bytes(0)
        });
    }

    function encodeExternalSellAction(
        uint256 _fromAccountId,
        uint256 _primaryMarketId,
        uint256 _secondaryMarketId,
        address _trader,
        uint256 _amountInWei,
        uint256 _amountOutMinWei,
        bytes memory _orderData
    ) internal pure returns (Actions.ActionArgs memory) {
        return Actions.ActionArgs({
            actionType : Actions.ActionType.Sell,
            accountId : _fromAccountId,
            // solium-disable-next-line arg-overflow
            amount : Types.AssetAmount(false, Types.AssetDenomination.Wei, Types.AssetReference.Delta, _amountInWei),
            primaryMarketId : _primaryMarketId,
            secondaryMarketId : _secondaryMarketId,
            otherAddress : _trader,
            otherAccountId : 0,
            data : abi.encode(_amountOutMinWei, _orderData)
        });
    }

    function encodeInternalTradeAction(
        uint256 _fromAccountId,
        uint256 _toAccountId,
        uint256 _primaryMarketId,
        uint256 _secondaryMarketId,
        address _traderAddress,
        uint256 _amountInWei,
        uint256 _amountOutWei
    ) internal pure returns (Actions.ActionArgs memory) {
        return Actions.ActionArgs({
            actionType : Actions.ActionType.Trade,
            accountId : _fromAccountId,
            // solium-disable-next-line arg-overflow
            amount : Types.AssetAmount(true, Types.AssetDenomination.Wei, Types.AssetReference.Delta, _amountInWei),
            primaryMarketId : _primaryMarketId,
            secondaryMarketId : _secondaryMarketId,
            otherAddress : _traderAddress,
            otherAccountId : _toAccountId,
            data : abi.encode(_amountOutWei)
        });
    }

    function encodeTransferAction(
        uint256 _fromAccountId,
        uint256 _toAccountId,
        uint256 _marketId,
        uint256 _amount
    ) internal pure returns (Actions.ActionArgs memory) {
        Types.AssetAmount memory assetAmount;
        if (_amount == uint(- 1)) {
            assetAmount = Types.AssetAmount(
                true,
                Types.AssetDenomination.Wei,
                Types.AssetReference.Target,
                0
            );
        } else {
            assetAmount = Types.AssetAmount(
                false,
                Types.AssetDenomination.Wei,
                Types.AssetReference.Delta,
                _amount
            );
        }
        return Actions.ActionArgs({
            actionType : Actions.ActionType.Transfer,
            accountId : _fromAccountId,
            amount : assetAmount,
            primaryMarketId : _marketId,
            secondaryMarketId : 0,
            otherAddress : address(0),
            otherAccountId : _toAccountId,
            data : bytes("")
        });
    }
}

