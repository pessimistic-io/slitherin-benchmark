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

import { Account } from "./Account.sol";
import { Actions } from "./Actions.sol";
import { Require } from "./Require.sol";
import { Types } from "./Types.sol";

import { AuthorizationBase } from "./AuthorizationBase.sol";
import { IBorrowPositionProxyV2 } from "./IBorrowPositionProxyV2.sol";
import { AccountActionLib } from "./AccountActionLib.sol";
import { AccountBalanceLib } from "./AccountBalanceLib.sol";

import { BorrowPositionProxyV1 } from "./BorrowPositionProxyV1.sol";



/**
 * @title   BorrowPositionProxyV2
 * @author  Dolomite
 *
 * @dev Proxy contract for opening borrow positions. This makes indexing easier and lowers gas costs on Arbitrum by
 *      minimizing call data
 */
contract BorrowPositionProxyV2 is IBorrowPositionProxyV2, BorrowPositionProxyV1, AuthorizationBase {

    constructor (
        address dolomiteMargin
    )
    public
    BorrowPositionProxyV1(dolomiteMargin)
    AuthorizationBase(dolomiteMargin)
    {}

    function openBorrowPositionWithDifferentAccounts(
        address _fromAccountOwner,
        uint256 _fromAccountNumber,
        address _toAccountOwner,
        uint256 _toAccountNumber,
        uint256 _marketId,
        uint256 _amountWei,
        AccountBalanceLib.BalanceCheckFlag _balanceCheckFlag
    )
    external
    requireIsCallerAuthorized(msg.sender) {
        // Emit this before the call to DolomiteMargin so indexers get it before the Transfer events are emitted
        emit BorrowPositionOpen(_toAccountOwner, _toAccountNumber);

        AccountActionLib.transfer(
            DOLOMITE_MARGIN,
            _fromAccountOwner,
            _fromAccountNumber,
            _toAccountOwner,
            _toAccountNumber,
            _marketId,
            Types.AssetAmount({
                sign: false,
                denomination: Types.AssetDenomination.Wei,
                ref: Types.AssetReference.Delta,
                value: _amountWei
            }),
            _balanceCheckFlag
        );
    }

    function closeBorrowPositionWithDifferentAccounts(
        address _borrowAccountOwner,
        uint256 _borrowAccountNumber,
        address _toAccountOwner,
        uint256 _toAccountNumber,
        uint256[] calldata _collateralMarketIds
    )
    external
    requireIsCallerAuthorized(msg.sender) {
        Account.Info[] memory accounts = new Account.Info[](2);
        accounts[0] = Account.Info(_borrowAccountOwner, _borrowAccountNumber);
        accounts[1] = Account.Info(_toAccountOwner, _toAccountNumber);

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](_collateralMarketIds.length);
        for (uint256 i = 0; i < _collateralMarketIds.length; i++) {
            actions[i] = AccountActionLib.encodeTransferAction(
                /* _fromAccountId = */ 0, // solium-disable-line
                /* _toAccountId = */ 1, // solium-disable-line
                _collateralMarketIds[i],
                uint(- 1)
            );
        }

        DOLOMITE_MARGIN.operate(accounts, actions);
    }

    function transferBetweenAccountsWithDifferentAccounts(
        address _fromAccountOwner,
        uint256 _fromAccountNumber,
        address _toAccountOwner,
        uint256 _toAccountNumber,
        uint256 _marketId,
        uint256 _amountWei,
        AccountBalanceLib.BalanceCheckFlag _balanceCheckFlag
    )
    external
    requireIsCallerAuthorized(msg.sender) {
        AccountActionLib.transfer(
            DOLOMITE_MARGIN,
            _fromAccountOwner,
            _fromAccountNumber,
            _toAccountOwner,
            _toAccountNumber,
            _marketId,
            Types.AssetAmount({
                sign: false,
                denomination: Types.AssetDenomination.Wei,
                ref: Types.AssetReference.Delta,
                value: _amountWei
            }),
            _balanceCheckFlag
        );
    }

    // solium-disable-next-line security/no-assign-params
    function repayAllForBorrowPositionWithDifferentAccounts(
        address _fromAccountOwner,
        uint256 _fromAccountNumber,
        address _borrowAccountOwner,
        uint256 _borrowAccountNumber,
        uint256 _marketId,
        AccountBalanceLib.BalanceCheckFlag _balanceCheckFlag
    )
    external
    requireIsCallerAuthorized(msg.sender) {
        // reverse the ordering of the `_borrowAccountNumber` and `_fromAccountNumber`, so using `Target = 0` calculates
        // on `_borrowAccountNumber`. We then need to reverse the `AccountBalanceLib.BalanceCheckFlag` if it's set to
        // `from` or `to`.
        if (_balanceCheckFlag == AccountBalanceLib.BalanceCheckFlag.To) {
            _balanceCheckFlag = AccountBalanceLib.BalanceCheckFlag.From;
        } else if (_balanceCheckFlag == AccountBalanceLib.BalanceCheckFlag.From) {
            _balanceCheckFlag = AccountBalanceLib.BalanceCheckFlag.To;
        }

        AccountActionLib.transfer(
            DOLOMITE_MARGIN,
            _borrowAccountOwner,
            _borrowAccountNumber,
            _fromAccountOwner,
            _fromAccountNumber,
            _marketId,
            Types.AssetAmount({
                sign: false,
                denomination: Types.AssetDenomination.Wei,
                ref: Types.AssetReference.Target,
                value: 0
            }),
            _balanceCheckFlag
        );
    }
}

