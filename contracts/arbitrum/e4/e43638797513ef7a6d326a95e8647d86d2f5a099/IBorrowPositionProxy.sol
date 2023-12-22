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

import { AccountBalanceHelper } from "./AccountBalanceHelper.sol";


interface IBorrowPositionProxy {

    // ========================= Events =========================

    event BorrowPositionOpen(address indexed _borrower, uint256 indexed _borrowAccountIndex);

    // ========================= Functions =========================

    /**
     * @param _fromAccountIndex     The index from which `msg.sender` will be sourcing the deposit
     * @param _toAccountIndex       The index into which `msg.sender` will be depositing
     * @param _collateralMarketId   The ID of the market being deposited
     * @param _amountWei            The amount, in Wei, to deposit
     * @param _balanceCheckFlag     Flag used to check if `_fromAccountIndex`, `_toAccountIndex`, or both accounts can
     *                              go negative after the transfer settles. Setting the flag to
     *                              `AccountBalanceHelper.BalanceCheckFlag.None=3` results in neither account being
     *                              checked.
     */
    function openBorrowPosition(
        uint256 _fromAccountIndex,
        uint256 _toAccountIndex,
        uint256 _collateralMarketId,
        uint256 _amountWei,
        AccountBalanceHelper.BalanceCheckFlag _balanceCheckFlag
    ) external;

    /**
     * @notice  This method can only be called once the user's debt has been reduced to zero. Sends all
     *          `_collateralMarketIds` from `_borrowAccountIndex` to `_toAccountIndex`.
     *
     * @param _borrowAccountIndex   The index from which `msg.sender` collateral will be withdrawn
     * @param _toAccountIndex       The index into which `msg.sender` will be depositing leftover collateral
     * @param _collateralMarketIds  The IDs of the markets being withdrawn, to close the position
     */
    function closeBorrowPosition(
        uint256 _borrowAccountIndex,
        uint256 _toAccountIndex,
        uint256[] calldata _collateralMarketIds
    ) external;

    /**
     * @param _fromAccountIndex The index from which `msg.sender` will be withdrawing assets
     * @param _toAccountIndex   The index into which `msg.sender` will be depositing assets
     * @param _marketId         The ID of the market being transferred
     * @param _amountWei        The amount, in Wei, to transfer
     * @param _balanceCheckFlag Flag used to check if `_fromAccountIndex`, `_toAccountIndex`, or both accounts can go
     *                          negative after the transfer settles. Setting the flag to
     *                          `AccountBalanceHelper.BalanceCheckFlag.None=3` results in neither account being checked.
     */
    function transferBetweenAccounts(
        uint256 _fromAccountIndex,
        uint256 _toAccountIndex,
        uint256 _marketId,
        uint256 _amountWei,
        AccountBalanceHelper.BalanceCheckFlag _balanceCheckFlag
    ) external;

    /**
     * @param _fromAccountIndex     The index from which `msg.sender` will be depositing assets
     * @param _borrowAccountIndex   The index of the borrow position for that will receive the deposited assets
     * @param _marketId             The ID of the market being transferred
     * @param _balanceCheckFlag     Flag used to check if `_fromAccountIndex`, `_borrowAccountIndex`, or both accounts
     *                              can go negative after the transfer settles. Setting the flag to
     *                              `AccountBalanceHelper.BalanceCheckFlag.None=3` results in neither account being
     *                              checked.
     */
    function repayAllForBorrowPosition(
        uint256 _fromAccountIndex,
        uint256 _borrowAccountIndex,
        uint256 _marketId,
        AccountBalanceHelper.BalanceCheckFlag _balanceCheckFlag
    ) external;
}

