// SPDX-License-Identifier: GPL-3.0-or-later
/*

    Copyright 2023 Dolomite

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

*/
pragma solidity ^0.8.9;

import { IDolomiteMargin } from "./IDolomiteMargin.sol";
import { IDolomiteStructs } from "./IDolomiteStructs.sol";
import { Require } from "./Require.sol";
import { TypesLib } from "./TypesLib.sol";
import { IGenericTraderProxyV1 } from "./IGenericTraderProxyV1.sol";
import { IIsolationModeTokenVaultV1 } from "./IIsolationModeTokenVaultV1.sol";
import { IIsolationModeVaultFactory } from "./IIsolationModeVaultFactory.sol";
import { AccountActionLib } from "./AccountActionLib.sol";
import { AccountBalanceLib } from "./AccountBalanceLib.sol";


/**
 * @title   IsolationModeTokenVaultV1ActionsImpl
 * @author  Dolomite
 *
 * Reusable library for functions that save bytecode on the async unwrapper/wrapper contracts
 */
library IsolationModeTokenVaultV1ActionsImpl {
    using TypesLib for IDolomiteMargin.Par;
    using TypesLib for IDolomiteMargin.Wei;

    // ===================================================
    // ==================== Constants ====================
    // ===================================================

    bytes32 private constant _FILE = "IsolationModeVaultV1ActionsImpl";

    // ===================================================
    // ==================== Functions ====================
    // ===================================================

    function depositIntoVaultForDolomiteMargin(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _toAccountNumber,
        uint256 _amountWei
    ) public {
        // This implementation requires we deposit into index 0
        _checkToAccountNumberIsZero(_toAccountNumber);
        IIsolationModeVaultFactory(_vault.VAULT_FACTORY()).depositIntoDolomiteMargin(_toAccountNumber, _amountWei);
    }

    function withdrawFromVaultForDolomiteMargin(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _fromAccountNumber,
        uint256 _amountWei
    ) public {
        // This implementation requires we withdraw from index 0
        _checkFromAccountNumberIsZero(_fromAccountNumber);
        IIsolationModeVaultFactory(_vault.VAULT_FACTORY()).withdrawFromDolomiteMargin(_fromAccountNumber, _amountWei);
    }

    function openBorrowPosition(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _fromAccountNumber,
        uint256 _toAccountNumber,
        uint256 _amountWei
    ) public {
        _checkFromAccountNumberIsZero(_fromAccountNumber);
        Require.that(
            _toAccountNumber != 0,
            _FILE,
            "Invalid toAccountNumber",
            _toAccountNumber
        );

        _vault.BORROW_POSITION_PROXY().openBorrowPosition(
            _fromAccountNumber,
            _toAccountNumber,
            _vault.marketId(),
            _amountWei,
            AccountBalanceLib.BalanceCheckFlag.Both
        );
    }

    function closeBorrowPositionWithUnderlyingVaultToken(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _borrowAccountNumber,
        uint256 _toAccountNumber
    ) public {
        _checkBorrowAccountNumberIsNotZero(_borrowAccountNumber);
        _checkToAccountNumberIsZero(_toAccountNumber);

        uint256[] memory collateralMarketIds = new uint256[](1);
        collateralMarketIds[0] = _vault.marketId();

        _vault.BORROW_POSITION_PROXY().closeBorrowPositionWithDifferentAccounts(
            /* _borrowAccountOwner = */ address(this),
            _borrowAccountNumber,
            /* _toAccountOwner = */ address(this),
            _toAccountNumber,
            collateralMarketIds
        );
    }

    function closeBorrowPositionWithOtherTokens(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _borrowAccountNumber,
        uint256 _toAccountNumber,
        uint256[] calldata _collateralMarketIds
    ) public {
        _checkBorrowAccountNumberIsNotZero(_borrowAccountNumber);
        uint256 underlyingMarketId = _vault.marketId();
        for (uint256 i = 0; i < _collateralMarketIds.length; i++) {
            Require.that(
                _collateralMarketIds[i] != underlyingMarketId,
                _FILE,
                "Cannot withdraw market to wallet",
                underlyingMarketId
            );
        }

        _vault.BORROW_POSITION_PROXY().closeBorrowPositionWithDifferentAccounts(
            /* _borrowAccountOwner = */ address(this),
            _borrowAccountNumber,
            /* _toAccountOwner = */ _vault.OWNER(),
            _toAccountNumber,
            _collateralMarketIds
        );
    }

    function transferIntoPositionWithUnderlyingToken(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _fromAccountNumber,
        uint256 _borrowAccountNumber,
        uint256 _amountWei
    ) public {
        _checkFromAccountNumberIsZero(_fromAccountNumber);
        _checkBorrowAccountNumberIsNotZero(_borrowAccountNumber);

        _vault.BORROW_POSITION_PROXY().transferBetweenAccounts(
            _fromAccountNumber,
            _borrowAccountNumber,
            _vault.marketId(),
            _amountWei,
            AccountBalanceLib.BalanceCheckFlag.Both
        );
    }

    function transferIntoPositionWithOtherToken(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _fromAccountNumber,
        uint256 _borrowAccountNumber,
        uint256 _marketId,
        uint256 _amountWei,
        AccountBalanceLib.BalanceCheckFlag _balanceCheckFlag,
        bool _checkAllowableCollateralMarketFlag
    ) public {
        _checkBorrowAccountNumberIsNotZero(_borrowAccountNumber);
        _checkMarketIdIsNotSelf(_vault, _marketId);

        _vault.BORROW_POSITION_PROXY().transferBetweenAccountsWithDifferentAccounts(
            /* _fromAccountOwner = */ _vault.OWNER(),
            _fromAccountNumber,
            /* _toAccountOwner = */ address(this),
            _borrowAccountNumber,
            _marketId,
            _amountWei,
            _balanceCheckFlag
        );

        if (_checkAllowableCollateralMarketFlag) {
            _checkAllowableCollateralMarket(
                _vault,
                address(this),
                _borrowAccountNumber,
                _marketId
            );
        }
    }

    function transferFromPositionWithUnderlyingToken(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _borrowAccountNumber,
        uint256 _toAccountNumber,
        uint256 _amountWei
    ) public {
        _checkBorrowAccountNumberIsNotZero(_borrowAccountNumber);
        _checkToAccountNumberIsZero(_toAccountNumber);

        _vault.BORROW_POSITION_PROXY().transferBetweenAccounts(
            _borrowAccountNumber,
            _toAccountNumber,
            _vault.marketId(),
            _amountWei,
            AccountBalanceLib.BalanceCheckFlag.Both
        );
    }

    function transferFromPositionWithOtherToken(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _borrowAccountNumber,
        uint256 _toAccountNumber,
        uint256 _marketId,
        uint256 _amountWei,
        AccountBalanceLib.BalanceCheckFlag _balanceCheckFlag
    ) public {
        _checkBorrowAccountNumberIsNotZero(_borrowAccountNumber);
        _checkMarketIdIsNotSelf(_vault, _marketId);

        _vault.BORROW_POSITION_PROXY().transferBetweenAccountsWithDifferentAccounts(
            /* _fromAccountOwner = */ address(this),
            _borrowAccountNumber,
            /* _toAccountOwner = */ _vault.OWNER(),
            _toAccountNumber,
            _marketId,
            _amountWei,
            _balanceCheckFlag
        );

        _checkAllowableDebtMarket(_vault, address(this), _borrowAccountNumber, _marketId);
    }

    function repayAllForBorrowPosition(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _fromAccountNumber,
        uint256 _borrowAccountNumber,
        uint256 _marketId,
        AccountBalanceLib.BalanceCheckFlag _balanceCheckFlag
    ) public {
        _checkBorrowAccountNumberIsNotZero(_borrowAccountNumber);
        _checkMarketIdIsNotSelf(_vault, _marketId);
        _vault.BORROW_POSITION_PROXY().repayAllForBorrowPositionWithDifferentAccounts(
            /* _fromAccountOwner = */ _vault.OWNER(),
            _fromAccountNumber,
            /* _borrowAccountOwner = */ address(this),
            _borrowAccountNumber,
            _marketId,
            _balanceCheckFlag
        );
    }

    function addCollateralAndSwapExactInputForOutput(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _fromAccountNumber,
        uint256 _borrowAccountNumber,
        uint256[] calldata _marketIdsPath,
        uint256 _inputAmountWei,
        uint256 _minOutputAmountWei,
        IGenericTraderProxyV1.TraderParam[] memory _tradersPath,
        IDolomiteMargin.AccountInfo[] memory _makerAccounts,
        IGenericTraderProxyV1.UserConfig memory _userConfig
    ) public {
        if (_marketIdsPath[0] == _vault.marketId()) {
            transferIntoPositionWithUnderlyingToken(
                _vault,
                _fromAccountNumber,
                _borrowAccountNumber,
                _inputAmountWei
            );
        } else {
            if (_inputAmountWei == AccountActionLib.all()) {
                _inputAmountWei = _getAndValidateBalanceForAllForMarket(
                    _vault,
                    _vault.OWNER(),
                    _fromAccountNumber,
                    _marketIdsPath[0]
                );
            }
            // we always swap the exact amount out; no need to check `BalanceCheckFlag.To`
            // always skip the checking allowable collateral, since we're immediately trading all of it here
            transferIntoPositionWithOtherToken(
                _vault,
                _fromAccountNumber,
                _borrowAccountNumber,
                _marketIdsPath[0],
                _inputAmountWei,
                AccountBalanceLib.BalanceCheckFlag.From,
                /* _checkAllowableCollateralMarketFlag = */ false
            );
        }

        swapExactInputForOutput(
            _vault,
            _borrowAccountNumber,
            _marketIdsPath,
            _inputAmountWei,
            _minOutputAmountWei,
            _tradersPath,
            _makerAccounts,
            _userConfig,
            /* _checkOutputMarketIdFlag = */ true
        );
    }

    function swapExactInputForOutputAndRemoveCollateral(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _toAccountNumber,
        uint256 _borrowAccountNumber,
        uint256[] calldata _marketIdsPath,
        uint256 _inputAmountWei,
        uint256 _minOutputAmountWei,
        IGenericTraderProxyV1.TraderParam[] memory _tradersPath,
        IDolomiteMargin.AccountInfo[] memory _makerAccounts,
        IGenericTraderProxyV1.UserConfig memory _userConfig
    ) public {
        uint256 outputMarketId = _marketIdsPath[_marketIdsPath.length - 1];
        IDolomiteStructs.Wei memory balanceDelta;

        // Create a new scope for stack too deep
        {
            IDolomiteMargin dolomiteMargin = _vault.DOLOMITE_MARGIN();
            IDolomiteStructs.AccountInfo memory borrowAccount = IDolomiteStructs.AccountInfo({
                owner: address(this),
                number: _borrowAccountNumber
            });
            // Validate the output balance before executing the swap
            IDolomiteStructs.Wei memory balanceBefore = dolomiteMargin.getAccountWei(borrowAccount, outputMarketId);

            swapExactInputForOutput(
                _vault,
                _borrowAccountNumber,
                _marketIdsPath,
                _inputAmountWei,
                _minOutputAmountWei,
                _tradersPath,
                _makerAccounts,
                _userConfig,
                /* _checkOutputMarketIdFlag = */ false
            );

            balanceDelta = dolomiteMargin
                .getAccountWei(borrowAccount, outputMarketId)
                .sub(balanceBefore);
        }

        // Panic if the balance delta is not positive
        assert(balanceDelta.isPositive());

        if (outputMarketId == _vault.marketId()) {
            transferFromPositionWithUnderlyingToken(
                /* _vault = */ _vault,
                _borrowAccountNumber,
                _toAccountNumber,
                balanceDelta.value
            );
        } else {
            transferFromPositionWithOtherToken(
                /* _vault = */ _vault,
                _borrowAccountNumber,
                _toAccountNumber,
                outputMarketId,
                balanceDelta.value,
                AccountBalanceLib.BalanceCheckFlag.None // we always transfer the exact amount out; no need to check
            );
        }
    }

    function swapExactInputForOutput(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _tradeAccountNumber,
        uint256[] calldata _marketIdsPath,
        uint256 _inputAmountWei,
        uint256 _minOutputAmountWei,
        IGenericTraderProxyV1.TraderParam[] memory _tradersPath,
        IDolomiteMargin.AccountInfo[] memory _makerAccounts,
        IGenericTraderProxyV1.UserConfig memory _userConfig,
        bool _checkOutputMarketIdFlag
    ) public {
        Require.that(
            _tradeAccountNumber != 0,
            _FILE,
            "Invalid tradeAccountNumber",
            _tradeAccountNumber
        );

        if (_inputAmountWei == AccountActionLib.all()) {
            _inputAmountWei = _getAndValidateBalanceForAllForMarket(
                _vault,
                /* _accountOwner = */ address(_vault),
                _tradeAccountNumber,
                _marketIdsPath[0]
            );
        }

        _vault.dolomiteRegistry().genericTraderProxy().swapExactInputForOutput(
            _tradeAccountNumber,
            _marketIdsPath,
            _inputAmountWei,
            _minOutputAmountWei,
            _tradersPath,
            _makerAccounts,
            _userConfig
        );

        uint256 inputMarketId = _marketIdsPath[0];
        uint256 outputMarketId = _marketIdsPath[_marketIdsPath.length - 1];
        address tradeAccountOwner = address(this);
        _checkAllowableCollateralMarket(_vault, tradeAccountOwner, _tradeAccountNumber, inputMarketId);
        _checkAllowableDebtMarket(_vault, tradeAccountOwner, _tradeAccountNumber, inputMarketId);
        if (_checkOutputMarketIdFlag) {
            _checkAllowableCollateralMarket(_vault, tradeAccountOwner, _tradeAccountNumber, outputMarketId);
            _checkAllowableDebtMarket(_vault, tradeAccountOwner, _tradeAccountNumber, outputMarketId);
        }
    }

    // ===================================================
    // ==================== Private ======================
    // ===================================================

    function _getAndValidateBalanceForAllForMarket(
        IIsolationModeTokenVaultV1 _vault,
        address _accountOwner,
        uint256 _accountNumber,
        uint256 _marketId
    ) private view returns (uint256) {
        IDolomiteStructs.Wei memory balanceWei = _vault.DOLOMITE_MARGIN().getAccountWei(
            IDolomiteStructs.AccountInfo({
                owner: _accountOwner,
                number: _accountNumber
            }),
            _marketId
        );
        Require.that(
            balanceWei.isPositive(),
            _FILE,
            "Invalid balance for transfer all"
        );
        return balanceWei.value;
    }

    function _checkAllowableCollateralMarket(
        IIsolationModeTokenVaultV1 _vault,
        address _accountOwner,
        uint256 _accountNumber,
        uint256 _marketId
    ) private view {
        // If the balance is positive, check that the collateral is for an allowable market. We use the Par balance
        // because, it uses less gas than getting the Wei balance, and we're only checking whether the balance is
        // positive.
        IDolomiteStructs.Par memory balancePar = _vault.DOLOMITE_MARGIN().getAccountPar(
            IDolomiteStructs.AccountInfo({
                owner: _accountOwner,
                number: _accountNumber
            }),
            _marketId
        );
        if (balancePar.isPositive()) {
            // Check the allowable collateral markets for the position:
            IIsolationModeVaultFactory vaultFactory = IIsolationModeVaultFactory(_vault.VAULT_FACTORY());
            uint256[] memory allowableCollateralMarketIds = vaultFactory.allowableCollateralMarketIds();
            uint256 allowableCollateralsLength = allowableCollateralMarketIds.length;
            if (allowableCollateralsLength != 0) {
                bool isAllowable = false;
                for (uint256 i = 0; i < allowableCollateralsLength; i++) {
                    if (allowableCollateralMarketIds[i] == _marketId) {
                        isAllowable = true;
                        break;
                    }
                }
                Require.that(
                    isAllowable,
                    _FILE,
                    "Market not allowed as collateral",
                    _marketId
                );
            }
        }
    }

    function _checkAllowableDebtMarket(
        IIsolationModeTokenVaultV1 _vault,
        address _accountOwner,
        uint256 _accountNumber,
        uint256 _marketId
    ) private view {
        // If the balance is negative, check that the debt is for an allowable market. We use the Par balance because,
        // it uses less gas than getting the Wei balance, and we're only checking whether the balance is negative.
        IDolomiteStructs.Par memory balancePar = _vault.DOLOMITE_MARGIN().getAccountPar(
            IDolomiteStructs.AccountInfo({
                owner: _accountOwner,
                number: _accountNumber
            }),
            _marketId
        );
        if (balancePar.isNegative()) {
            // Check the allowable debt markets for the position:
            IIsolationModeVaultFactory vaultFactory = IIsolationModeVaultFactory(_vault.VAULT_FACTORY());
            uint256[] memory allowableDebtMarketIds = vaultFactory.allowableDebtMarketIds();
            if (allowableDebtMarketIds.length != 0) {
                bool isAllowable = false;
                for (uint256 i = 0; i < allowableDebtMarketIds.length; i++) {
                    if (allowableDebtMarketIds[i] == _marketId) {
                        isAllowable = true;
                        break;
                    }
                }
                Require.that(
                    isAllowable,
                    _FILE,
                    "Market not allowed as debt",
                    _marketId
                );
            }
        }
    }

    function _checkMarketIdIsNotSelf(
        IIsolationModeTokenVaultV1 _vault,
        uint256 _marketId
    ) private view {
        Require.that(
            _marketId != _vault.marketId(),
            _FILE,
            "Invalid marketId",
            _marketId
        );
    }

    function _checkFromAccountNumberIsZero(uint256 _fromAccountNumber) private pure {
        Require.that(
            _fromAccountNumber == 0,
            _FILE,
            "Invalid fromAccountNumber",
            _fromAccountNumber
        );
    }

    function _checkToAccountNumberIsZero(uint256 _toAccountNumber) private pure {
        Require.that(
            _toAccountNumber == 0,
            _FILE,
            "Invalid toAccountNumber",
            _toAccountNumber
        );
    }

    function _checkBorrowAccountNumberIsNotZero(uint256 _borrowAccountNumber) private pure {
        Require.that(
            _borrowAccountNumber != 0,
            _FILE,
            "Invalid borrowAccountNumber",
            _borrowAccountNumber
        );
    }
}

