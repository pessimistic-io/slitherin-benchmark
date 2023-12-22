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

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

import { IDolomiteMargin } from "./IDolomiteMargin.sol";

import { Require } from "./Require.sol";

import { OnlyDolomiteMargin } from "./OnlyDolomiteMargin.sol";

import { IDolomiteMarginWrapperTrader } from "./IDolomiteMarginWrapperTrader.sol";
import { IWrappedTokenUserVaultFactory } from "./IWrappedTokenUserVaultFactory.sol";

import { AccountActionLib } from "./AccountActionLib.sol";


/**
 * @title   WrappedTokenUserVaultWrapperTrader
 * @author  Dolomite
 *
 * @notice  Abstract contract for wrapping a token into a VaultWrapperFactory token. Must be set as a token converter
 *          for the VaultWrapperFactory token.
 */
abstract contract WrappedTokenUserVaultWrapperTrader is IDolomiteMarginWrapperTrader, OnlyDolomiteMargin {
    using SafeERC20 for IERC20;

    // ======================== Constants ========================

    bytes32 private constant _FILE = "WrappedTokenUserVaultWrapper";
    uint256 private constant _ACTIONS_LENGTH = 1;

    // ======================== Field Variables ========================

    IWrappedTokenUserVaultFactory public immutable VAULT_FACTORY; // solhint-disable-line var-name-mixedcase

    // ======================== Constructor ========================

    constructor(
        address _vaultFactory,
        address _dolomiteMargin
    ) OnlyDolomiteMargin(_dolomiteMargin) {
        VAULT_FACTORY = IWrappedTokenUserVaultFactory(_vaultFactory);
    }

    // ======================== External Functions ========================

    function exchange(
        address _tradeOriginator,
        address _receiver,
        address _outputToken,
        address _inputToken,
        uint256 _inputAmount,
        bytes calldata _orderData
    )
    external
    onlyDolomiteMargin(msg.sender)
    returns (uint256) {
        Require.that(
            _outputToken == address(VAULT_FACTORY),
            _FILE,
            "Invalid output token",
            _outputToken
        );
        Require.that(
            _inputAmount > 0,
            _FILE,
            "Invalid input amount"
        );

        (uint256 minOutputAmount) = abi.decode(_orderData, (uint256));

        uint256 outputAmount = _exchangeIntoUnderlyingToken(
            _tradeOriginator,
            _receiver,
            VAULT_FACTORY.UNDERLYING_TOKEN(),
            minOutputAmount,
            _inputToken,
            _inputAmount,
            _orderData
        );
        Require.that(
            outputAmount >= minOutputAmount,
            _FILE,
            "Insufficient output amount",
            outputAmount,
            minOutputAmount
        );

        _approveWrappedTokenForTransfer(_tradeOriginator, _receiver, outputAmount);

        return outputAmount;
    }

    function createActionsForWrapping(
        uint256 _solidAccountId,
        uint256,
        address,
        address,
        uint256 _owedMarket,
        uint256 _heldMarket,
        uint256,
        uint256 _heldAmount
    )
    external
    override
    view
    returns (IDolomiteMargin.ActionArgs[] memory) {
        Require.that(
            DOLOMITE_MARGIN.getMarketTokenAddress(_owedMarket) == address(VAULT_FACTORY),
            _FILE,
            "Invalid owed market",
            _owedMarket
        );
        IDolomiteMargin.ActionArgs[] memory actions = new IDolomiteMargin.ActionArgs[](_ACTIONS_LENGTH);

        uint256 amountOut = getExchangeCost(
            DOLOMITE_MARGIN.getMarketTokenAddress(_heldMarket),
            DOLOMITE_MARGIN.getMarketTokenAddress(_owedMarket),
            _heldAmount,
            /* _orderData = */ bytes("")
        );

        actions[0] = AccountActionLib.encodeExternalSellAction(
            _solidAccountId,
            _heldMarket,
            _owedMarket,
            /* _trader = */ address(this),
            /* _amountInWei = */ _heldAmount,
            /* _amountOutMinWei = */ amountOut,
            bytes("")
        );

        return actions;
    }

    function actionsLength() external override pure returns (uint256) {
        return _ACTIONS_LENGTH;
    }

    function getExchangeCost(
        address _inputToken,
        address _outputToken,
        uint256 _desiredInputAmount,
        bytes memory _orderData
    )
    public
    override
    virtual
    view
    returns (uint256);

    // ============ Internal Functions ============

    /**
     * @notice Performs the exchange from `_inputToken` (could be anything) into the factory's underlying token.
     */
    function _exchangeIntoUnderlyingToken(
        address _tradeOriginator,
        address _receiver,
        address _outputTokenUnderlying,
        uint256 _minOutputAmount,
        address _inputToken,
        uint256 _inputAmount,
        bytes memory _orderData
    ) internal virtual returns (uint256);

    function _approveWrappedTokenForTransfer(
        address _vault,
        address _receiver,
        uint256 _amount
    )
    internal
    virtual {
        VAULT_FACTORY.enqueueTransferIntoDolomiteMargin(_vault, _amount);

        address underlyingToken = VAULT_FACTORY.UNDERLYING_TOKEN();
        IERC20(underlyingToken).safeApprove(_vault, _amount);
        IERC20(address(VAULT_FACTORY)).safeApprove(_receiver, _amount);
    }
}

