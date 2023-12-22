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

import { AccountActionHelper } from "./AccountActionHelper.sol";
import { AccountBalanceHelper } from "./AccountBalanceHelper.sol";
import { OnlyDolomiteMargin } from "./OnlyDolomiteMargin.sol";

import { IDepositWithdrawalProxy } from "./IDepositWithdrawalProxy.sol";
import { IWETH } from "./IWETH.sol";


/**
 * @title DepositWithdrawalProxy
 * @author Dolomite
 *
 * @dev Contract for depositing or withdrawing to/from Dolomite easily. This lowers gas costs on Arbitrum by minimizing
 *      callData
 */
contract DepositWithdrawalProxy is IDepositWithdrawalProxy, OnlyDolomiteMargin, ReentrancyGuard {
    using Address for address payable;

    // ============ Constants ============

    bytes32 constant FILE = "DepositWithdrawalProxy";

    // ============ Field Variables ============

    IWETH WETH;
    uint256 ETH_MARKET_ID;
    bool g_initialized;

    // ============ Modifiers ============

    modifier requireIsInitialized() {
        Require.that(
            g_initialized,
            FILE,
            "not initialized"
        );
        _;
    }

    // ============ Constructor ============

    constructor (
        address _dolomiteMargin
    )
    public
    OnlyDolomiteMargin(_dolomiteMargin)
    {}

    // ============ External Functions ============

    function() external payable {
        Require.that(
            msg.sender == address(WETH),
            FILE,
            "invalid ETH sender"
        );
    }

    function initializeETHMarket(
        address payable _weth
    ) external {
        Require.that(
            !g_initialized,
            FILE,
            "already initialized"
        );
        g_initialized = true;
        WETH = IWETH(_weth);
        ETH_MARKET_ID = DOLOMITE_MARGIN.getMarketIdByTokenAddress(_weth);
        WETH.approve(address(DOLOMITE_MARGIN), uint(-1));
    }

    function depositWei(
        uint256 _toAccountNumber,
        uint256 _marketId,
        uint256 _amountWei
    )
    external
    nonReentrant {
        AccountActionHelper.deposit(
            DOLOMITE_MARGIN,
            /* _accountOwner = */ msg.sender, // solium-disable-line indentation
            /* _fromAccount = */ msg.sender, // solium-disable-line indentation
            _toAccountNumber,
            _marketId,
            Types.AssetAmount({
                sign: true,
                denomination: Types.AssetDenomination.Wei,
                ref: Types.AssetReference.Delta,
                value: _amountWei == uint(-1) ? _getSenderBalance(_marketId) : _amountWei
            })
        );
    }

    function depositETH(
        uint256 _toAccountNumber
    )
    external
    payable
    requireIsInitialized
    nonReentrant {
        _wrap();
        AccountActionHelper.deposit(
            DOLOMITE_MARGIN,
            /* _accountOwner = */ msg.sender, // solium-disable-line indentation
            /* _fromAccount = */ address(this), // solium-disable-line indentation
            _toAccountNumber,
            ETH_MARKET_ID,
            Types.AssetAmount({
                sign: true,
                denomination: Types.AssetDenomination.Wei,
                ref: Types.AssetReference.Delta,
                value: msg.value
            })
        );
    }

    function depositWeiIntoDefaultAccount(
        uint256 _marketId,
        uint256 _amountWei
    )
    external
    nonReentrant {
        AccountActionHelper.deposit(
            DOLOMITE_MARGIN,
            /* _accountOwner = */ msg.sender, // solium-disable-line indentation
            /* _fromAccount = */ msg.sender, // solium-disable-line indentation
            /* _toAccountNumber = */ 0, // solium-disable-line indentation
            _marketId,
            Types.AssetAmount({
                sign: true,
                denomination: Types.AssetDenomination.Wei,
                ref: Types.AssetReference.Delta,
                value: _amountWei == uint(-1) ? _getSenderBalance(_marketId) : _amountWei
            })
        );
    }

    function depositETHIntoDefaultAccount()
    external
    payable
    requireIsInitialized
    nonReentrant {
        _wrap();
        AccountActionHelper.deposit(
            DOLOMITE_MARGIN,
            /* _accountOwner = */ msg.sender, // solium-disable-line indentation
            /* _fromAccount = */ address(this), // solium-disable-line indentation
            /* _toAccountNumber = */ 0, // solium-disable-line indentation
            ETH_MARKET_ID,
            Types.AssetAmount({
                sign: true,
                denomination: Types.AssetDenomination.Wei,
                ref: Types.AssetReference.Delta,
                value: msg.value
            })
        );
    }

    function withdrawWei(
        uint256 _fromAccountNumber,
        uint256 _marketId,
        uint256 _amountWei,
        AccountBalanceHelper.BalanceCheckFlag _balanceCheckFlag
    )
    external
    nonReentrant {
        AccountActionHelper.withdraw(
            DOLOMITE_MARGIN,
            /* _accountOwner = */ msg.sender, // solium-disable-line indentation
            _fromAccountNumber,
            /* _toAccount = */ msg.sender, // solium-disable-line indentation
            _marketId,
            Types.AssetAmount({
                sign: false,
                denomination: Types.AssetDenomination.Wei,
                ref: _amountWei == uint(-1) ? Types.AssetReference.Target : Types.AssetReference.Delta,
                value: _amountWei == uint(-1) ? 0 : _amountWei
            }),
            _balanceCheckFlag
        );
    }

    function withdrawETH(
        uint256 _fromAccountNumber,
        uint256 _amountWei,
        AccountBalanceHelper.BalanceCheckFlag _balanceCheckFlag
    )
    external
    requireIsInitialized
    nonReentrant {
        AccountActionHelper.withdraw(
            DOLOMITE_MARGIN,
            /* _accountOwner = */ msg.sender, // solium-disable-line indentation
            _fromAccountNumber,
            /* _toAccount = */ address(this), // solium-disable-line indentation
            ETH_MARKET_ID,
            Types.AssetAmount({
                sign: false,
                denomination: Types.AssetDenomination.Wei,
                ref: _amountWei == uint(-1) ? Types.AssetReference.Target : Types.AssetReference.Delta,
                value: _amountWei == uint(-1) ? 0 : _amountWei
            }),
            _balanceCheckFlag
        );
        _unwrapAndSend();
    }

    function withdrawWeiFromDefaultAccount(
        uint256 _marketId,
        uint256 _amountWei,
        AccountBalanceHelper.BalanceCheckFlag _balanceCheckFlag
    )
    external
    nonReentrant {
        AccountActionHelper.withdraw(
            DOLOMITE_MARGIN,
            /* _accountOwner = */ msg.sender, // solium-disable-line indentation
            /* _fromAccountNumber = */ 0, // solium-disable-line indentation
            /* _toAccount = */ msg.sender, // solium-disable-line indentation
            _marketId,
            Types.AssetAmount({
                sign: false,
                denomination: Types.AssetDenomination.Wei,
                ref: _amountWei == uint(-1) ? Types.AssetReference.Target : Types.AssetReference.Delta,
                value: _amountWei == uint(-1) ? 0 : _amountWei
            }),
            _balanceCheckFlag
        );
    }

    function withdrawETHFromDefaultAccount(
        uint256 _amountWei,
        AccountBalanceHelper.BalanceCheckFlag _balanceCheckFlag
    )
    external
    requireIsInitialized
    nonReentrant {
        AccountActionHelper.withdraw(
            DOLOMITE_MARGIN,
            /* _accountOwner = */ msg.sender, // solium-disable-line indentation
            /* _fromAccountNumber = */ 0, // solium-disable-line indentation
            /* _toAccount = */ address(this), // solium-disable-line indentation
            ETH_MARKET_ID,
            Types.AssetAmount({
                sign: false,
                denomination: Types.AssetDenomination.Wei,
                ref: _amountWei == uint(-1) ? Types.AssetReference.Target : Types.AssetReference.Delta,
                value: _amountWei == uint(-1) ? 0 : _amountWei
            }),
            _balanceCheckFlag
        );
        _unwrapAndSend();
    }

    // ========================= Par Functions =========================

    function depositPar(
        uint256 _toAccountNumber,
        uint256 _marketId,
        uint256 _amountPar
    )
    external
    nonReentrant {
        AccountActionHelper.deposit(
            DOLOMITE_MARGIN,
            /* _accountOwner = */ msg.sender, // solium-disable-line indentation
            /* _fromAccount = */ msg.sender, // solium-disable-line indentation
            _toAccountNumber,
            _marketId,
            Types.AssetAmount({
                sign: true,
                denomination: Types.AssetDenomination.Par,
                ref: Types.AssetReference.Delta,
                value: _amountPar
            })
        );
    }

    function depositParIntoDefaultAccount(
        uint256 _marketId,
        uint256 _amountPar
    )
    external
    nonReentrant {
        AccountActionHelper.deposit(
            DOLOMITE_MARGIN,
            /* _accountOwner = */ msg.sender, // solium-disable-line indentation
            /* _fromAccount = */ msg.sender, // solium-disable-line indentation
            /* _toAccountNumber = */ 0, // solium-disable-line indentation
            _marketId,
            Types.AssetAmount({
                sign: true,
                denomination: Types.AssetDenomination.Par,
                ref: Types.AssetReference.Delta,
                value: _amountPar
            })
        );
    }

    function withdrawPar(
        uint256 _fromAccountNumber,
        uint256 _marketId,
        uint256 _amountPar,
        AccountBalanceHelper.BalanceCheckFlag _balanceCheckFlag
    )
    external
    nonReentrant {
        AccountActionHelper.withdraw(
            DOLOMITE_MARGIN,
            /* _accountOwner = */ msg.sender, // solium-disable-line indentation
            _fromAccountNumber,
            /* _toAccount = */ msg.sender, // solium-disable-line indentation
            _marketId,
            Types.AssetAmount({
                sign: false,
                denomination: Types.AssetDenomination.Par,
                ref: _amountPar == uint(-1) ? Types.AssetReference.Target : Types.AssetReference.Delta,
                value: _amountPar == uint(-1) ? 0 : _amountPar
            }),
            _balanceCheckFlag
        );
    }

    function withdrawParFromDefaultAccount(
        uint256 _marketId,
        uint256 _amountPar,
        AccountBalanceHelper.BalanceCheckFlag _balanceCheckFlag
    )
    external
    nonReentrant {
        AccountActionHelper.withdraw(
            DOLOMITE_MARGIN,
            /* _accountOwner = */ msg.sender, // solium-disable-line indentation
            /* _fromAccountNumber = */ 0, // solium-disable-line indentation
            /* _toAccount = */ msg.sender, // solium-disable-line indentation
            _marketId,
            Types.AssetAmount({
                sign: false,
                denomination: Types.AssetDenomination.Par,
                ref: _amountPar == uint(-1) ? Types.AssetReference.Target : Types.AssetReference.Delta,
                value: _amountPar == uint(-1) ? 0 : _amountPar
            }),
            _balanceCheckFlag
        );
    }

    // ============ Internal Functions ============

    function _wrap() internal {
        WETH.deposit.value(msg.value)();
    }

    function _unwrapAndSend() internal {
        IWETH _WETH = WETH;
        uint amount = _WETH.balanceOf(address(this));
        _WETH.withdraw(amount);
        msg.sender.sendValue(amount);
    }

    function _getSenderBalance(uint256 _marketId) internal view returns (uint) {
        return IERC20(DOLOMITE_MARGIN.getMarketTokenAddress(_marketId)).balanceOf(msg.sender);
    }
}

