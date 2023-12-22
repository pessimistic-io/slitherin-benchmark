/*

    Copyright 2023 Dolomite.

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

import { Account } from "./Account.sol";
import { Actions } from "./Actions.sol";
import { Events } from "./Events.sol";
import { Require } from "./Require.sol";

import { OnlyDolomiteMargin } from "./OnlyDolomiteMargin.sol";

import { IMarginPositionRegistry } from "./IMarginPositionRegistry.sol";


/**
 * @title   MarginPositionRegistry
 * @author  Dolomite
 *
 * @dev Proxy contract for emitting events for a singular address when a margin position is opened or closed
 */
contract MarginPositionRegistry is IMarginPositionRegistry, OnlyDolomiteMargin {

    // ============ Constructor ============

    constructor (
        address dolomiteMargin
    )
    public
    OnlyDolomiteMargin(dolomiteMargin)
    {
        // solhint-disable-line no-empty-blocks
    }

    function emitMarginPositionOpen(
        address _accountOwner,
        uint256 _accountNumber,
        address _inputToken,
        address _outputToken,
        address _depositToken,
        Events.BalanceUpdate memory _inputBalanceUpdate,
        Events.BalanceUpdate memory _outputBalanceUpdate,
        Events.BalanceUpdate memory _marginDepositUpdate
    )
        public
        onlyGlobalOperator(msg.sender)
    {
        emit MarginPositionOpen(
            _accountOwner,
            _accountNumber,
            _inputToken,
            _outputToken,
            _depositToken,
            _inputBalanceUpdate,
            _outputBalanceUpdate,
            _marginDepositUpdate
        );
    }

    function emitMarginPositionClose(
        address _accountOwner,
        uint256 _accountNumber,
        address _inputToken,
        address _outputToken,
        address _withdrawalToken,
        Events.BalanceUpdate memory _inputBalanceUpdate,
        Events.BalanceUpdate memory _outputBalanceUpdate,
        Events.BalanceUpdate memory _marginWithdrawalUpdate
    )
        public
        onlyGlobalOperator(msg.sender)
    {
        emit MarginPositionClose(
            _accountOwner,
            _accountNumber,
            _inputToken,
            _outputToken,
            _withdrawalToken,
            _inputBalanceUpdate,
            _outputBalanceUpdate,
            _marginWithdrawalUpdate
        );
    }

}

