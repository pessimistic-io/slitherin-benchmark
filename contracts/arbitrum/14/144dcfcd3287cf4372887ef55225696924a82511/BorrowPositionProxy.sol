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

import { Address } from "./Address.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { IERC20 } from "./IERC20.sol";

import { IDolomiteMargin } from "./IDolomiteMargin.sol";

import { Account } from "./Account.sol";
import { Actions } from "./Actions.sol";
import { Require } from "./Require.sol";
import { Types } from "./Types.sol";

import { OnlyDolomiteMargin } from "./OnlyDolomiteMargin.sol";

import { IBorrowPositionProxy } from "./IBorrowPositionProxy.sol";


/**
 * @title   BorrowPositionProxy
 * @author  Dolomite
 *
 * @dev Proxy contract for opening borrow positions. This makes indexing easier and lowers gas costs on Arbitrum by
 *      minimizing call data
 */
contract BorrowPositionProxy is IBorrowPositionProxy, OnlyDolomiteMargin, ReentrancyGuard {

    constructor (
        address dolomiteMargin
    )
    public
    OnlyDolomiteMargin(dolomiteMargin)
    {}

    function openBorrowPosition(
        uint _fromAccountIndex,
        uint _toAccountIndex,
        uint _marketId,
        uint _amountWei
    ) external {
        Account.Info[] memory accounts = new Account.Info[](2);
        accounts[0] = Account.Info(msg.sender, _fromAccountIndex);
        accounts[1] = Account.Info(msg.sender, _toAccountIndex);

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        Types.AssetAmount memory assetAmount = Types.AssetAmount({
            sign: false,
            denomination: Types.AssetDenomination.Wei,
            ref: Types.AssetReference.Delta,
            value: _amountWei
        });
        actions[0] = Actions.ActionArgs({
            actionType : Actions.ActionType.Transfer,
            accountId : 0,
            amount : assetAmount,
            primaryMarketId : _marketId,
            secondaryMarketId : 0,
            otherAddress : address(0),
            otherAccountId : 1,
            data : bytes("")
        });

        // Emit this before the call to DolomiteMargin so indexers get it before the Transfer events are emitted
        emit BorrowPositionOpen(msg.sender, _toAccountIndex);

        IDolomiteMargin(DOLOMITE_MARGIN).operate(accounts, actions);
    }

    function closeBorrowPosition(
        uint _borrowAccountIndex,
        uint _toAccountIndex,
        uint[] calldata _collateralMarketIds
    ) external {
        Account.Info[] memory accounts = new Account.Info[](2);
        accounts[0] = Account.Info(msg.sender, _borrowAccountIndex);
        accounts[1] = Account.Info(msg.sender, _toAccountIndex);

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](_collateralMarketIds.length);
        Types.AssetAmount memory assetAmount = Types.AssetAmount({
            sign: false,
            denomination: Types.AssetDenomination.Wei,
            ref: Types.AssetReference.Target,
            value: 0
        });

        for (uint i = 0; i < _collateralMarketIds.length; i++) {
            actions[i] = Actions.ActionArgs({
                actionType : Actions.ActionType.Transfer,
                accountId : 0,
                amount : assetAmount,
                primaryMarketId : _collateralMarketIds[i],
                secondaryMarketId : 0,
                otherAddress : address(0),
                otherAccountId : 1,
                data : bytes("")
            });
        }

        IDolomiteMargin(DOLOMITE_MARGIN).operate(accounts, actions);
    }

    function transferBetweenAccounts(
        uint _fromAccountIndex,
        uint _toAccountIndex,
        uint _marketId,
        uint _amountWei
    ) external {
        Account.Info[] memory accounts = new Account.Info[](2);
        accounts[0] = Account.Info(msg.sender, _fromAccountIndex);
        accounts[1] = Account.Info(msg.sender, _toAccountIndex);

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        Types.AssetAmount memory assetAmount = Types.AssetAmount({
            sign: false,
            denomination: Types.AssetDenomination.Wei,
            ref: Types.AssetReference.Delta,
            value: _amountWei
        });
        actions[0] = Actions.ActionArgs({
            actionType : Actions.ActionType.Transfer,
            accountId : 0,
            amount : assetAmount,
            primaryMarketId : _marketId,
            secondaryMarketId : 0,
            otherAddress : address(0),
            otherAccountId : 1,
            data : bytes("")
        });

        IDolomiteMargin(DOLOMITE_MARGIN).operate(accounts, actions);
    }

    function repayAllForBorrowPosition(
        uint _fromAccountIndex,
        uint _borrowAccountIndex,
        uint _marketId
    ) external {
        Account.Info[] memory accounts = new Account.Info[](2);
        accounts[0] = Account.Info(msg.sender, _borrowAccountIndex);
        accounts[1] = Account.Info(msg.sender, _fromAccountIndex);

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
        // This works by transferring all debt from _borrowAccountIndex to _fromAccountIndex
        Types.AssetAmount memory assetAmount = Types.AssetAmount({
            sign: false,
            denomination: Types.AssetDenomination.Wei,
            ref: Types.AssetReference.Target,
            value: 0
        });
        actions[0] = Actions.ActionArgs({
            actionType : Actions.ActionType.Transfer,
            accountId : 0,
            amount : assetAmount,
            primaryMarketId : _marketId,
            secondaryMarketId : 0,
            otherAddress : address(0),
            otherAccountId : 1,
            data : bytes("")
        });

        IDolomiteMargin(DOLOMITE_MARGIN).operate(accounts, actions);
    }
}

