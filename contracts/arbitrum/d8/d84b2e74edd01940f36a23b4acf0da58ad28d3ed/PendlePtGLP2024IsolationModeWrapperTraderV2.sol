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
import { Require } from "./Require.sol";
import { IGmxRegistryV1 } from "./IGmxRegistryV1.sol";
import { IPendlePtGLP2024Registry } from "./IPendlePtGLP2024Registry.sol";
import { IPendleRouter } from "./IPendleRouter.sol";
import { IsolationModeWrapperTraderV2 } from "./IsolationModeWrapperTraderV2.sol";


/**
 * @title   PendlePtGLP2024IsolationModeWrapperTraderV2
 * @author  Dolomite
 *
 * @notice  Used for wrapping ptGLP (via swapping against the Pendle AMM then redeeming the underlying GLP to
 *          USDC).
 */
contract PendlePtGLP2024IsolationModeWrapperTraderV2 is IsolationModeWrapperTraderV2 {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    bytes32 private constant _FILE = "PendlePtGLP2024WrapperV2";

    // ============ Constructor ============

    IPendlePtGLP2024Registry public immutable PENDLE_REGISTRY; // solhint-disable-line var-name-mixedcase
    IGmxRegistryV1 public immutable GMX_REGISTRY; // solhint-disable-line var-name-mixedcase

    // ============ Constructor ============

    constructor(
        address _pendleRegistry,
        address _gmxRegistry,
        address _dptGlp,
        address _dolomiteMargin
    )
    IsolationModeWrapperTraderV2(
        _dptGlp,
        _dolomiteMargin
    ) {
        PENDLE_REGISTRY = IPendlePtGLP2024Registry(_pendleRegistry);
        GMX_REGISTRY = IGmxRegistryV1(_gmxRegistry);
    }

    // ============================================
    // ============= Public Functions =============
    // ============================================

    function isValidInputToken(address _inputToken) public override view returns (bool) {
        return GMX_REGISTRY.gmxVault().whitelistedTokens(_inputToken);
    }

    // ============================================
    // ============ Internal Functions ============
    // ============================================

    function _exchangeIntoUnderlyingToken(
        address,
        address,
        address,
        uint256 _minOutputAmount,
        address _inputToken,
        uint256 _inputAmount,
        bytes memory _extraOrderData
    )
        internal
        override
        returns (uint256)
    {
        (
            IPendleRouter.ApproxParams memory guessPtOut,
            IPendleRouter.TokenInput memory tokenInput
        ) = abi.decode(_extraOrderData, (IPendleRouter.ApproxParams, IPendleRouter.TokenInput));

        // approve input token and mint GLP
        IERC20(_inputToken).safeApprove(address(GMX_REGISTRY.glpManager()), _inputAmount);
        uint256 glpAmount = GMX_REGISTRY.glpRewardsRouter().mintAndStakeGlp(
            _inputToken,
            _inputAmount,
            /* _minUsdg = */ 0,
            /* _minGlp = */ 0
        );

        uint256 ptGlpAmount;
        {
            // Create a new scope to avoid stack too deep errors
            // approve GLP and swap for ptGLP
            IPendleRouter pendleRouter = PENDLE_REGISTRY.pendleRouter();
            IERC20(GMX_REGISTRY.sGlp()).safeApprove(address(pendleRouter), glpAmount);
            (ptGlpAmount,) = pendleRouter.swapExactTokenForPt(
                /* _receiver = */ address(this),
                address(PENDLE_REGISTRY.ptGlpMarket()),
                _minOutputAmount,
                guessPtOut,
                tokenInput
            );
        }

        return ptGlpAmount;
    }

    function _getExchangeCost(
        address,
        address,
        uint256,
        bytes memory
    )
    internal
    override
    pure
    returns (uint256)
    {
        revert(string(abi.encodePacked(Require.stringifyTruncated(_FILE), ": getExchangeCost is not implemented")));
    }
}

