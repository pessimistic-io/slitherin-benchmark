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

import { WETH9 } from "./WETH9.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { Account } from "./Account.sol";
import { Actions } from "./Actions.sol";
import { Require } from "./Require.sol";
import { OnlyDolomiteMargin } from "./OnlyDolomiteMargin.sol";


/**
 * @title PayableProxy
 * @author dYdX
 *
 * Contract for wrapping/unwrapping ETH before/after interacting with DolomiteMargin
 */
contract PayableProxy is OnlyDolomiteMargin, ReentrancyGuard {
    // ============ Constants ============

    bytes32 constant FILE = "PayableProxy";

    // ============ Storage ============

    WETH9 public WETH;

    // ============ Constructor ============

    constructor (
        address dolomiteMargin,
        address payable weth
    )
        public
        OnlyDolomiteMargin(dolomiteMargin)
    {
        WETH = WETH9(weth);
        WETH.approve(dolomiteMargin, uint256(-1));
    }

    // ============ Public Functions ============

    /**
     * Fallback function. Disallows ether to be sent to this contract without data except when
     * unwrapping WETH.
     */
    function ()
        external
        payable
    {
        require( // coverage-disable-line
            msg.sender == address(WETH),
            "Cannot receive ETH"
        );
    }

    function operate(
        Account.Info[] memory accounts,
        Actions.ActionArgs[] memory actions,
        address payable sendEthTo
    )
        public
        payable
        nonReentrant
    {
        WETH9 weth = WETH;

        // create WETH from ETH
        if (msg.value != 0) {
            weth.deposit.value(msg.value)();
        }

        // validate the input
        for (uint256 i = 0; i < actions.length; i++) {
            Actions.ActionArgs memory action = actions[i];

            // Can only operate on accounts owned by msg.sender
            address owner1 = accounts[action.accountId].owner;
            Require.that(
                owner1 == msg.sender,
                FILE,
                "Sender must be primary account",
                owner1
            );

            // For a transfer both accounts must be owned by msg.sender
            if (action.actionType == Actions.ActionType.Transfer) {
                address owner2 = accounts[action.otherAccountId].owner;
                Require.that(
                    owner2 == msg.sender,
                    FILE,
                    "Sender must be secondary account",
                    owner2
                );
            } else {
                Require.that(
                    action.actionType != Actions.ActionType.Liquidate,
                    FILE,
                    "Cannot perform liquidations"
                );
                if (
                    action.actionType == Actions.ActionType.Trade &&
                    DOLOMITE_MARGIN.getIsAutoTraderSpecial(action.otherAddress)
                ) {
                    Require.that(
                        DOLOMITE_MARGIN.getIsGlobalOperator(msg.sender),
                        FILE,
                        "Unpermissioned trade operator"
                    );
                }
            }
        }

        DOLOMITE_MARGIN.operate(accounts, actions);

        // return all remaining WETH to the sendEthTo as ETH
        uint256 remainingWeth = weth.balanceOf(address(this));
        if (remainingWeth != 0) {
            Require.that(
                sendEthTo != address(0),
                FILE,
                "Must set sendEthTo"
            );

            weth.withdraw(remainingWeth);
            sendEthTo.transfer(remainingWeth);
        }
    }
}

