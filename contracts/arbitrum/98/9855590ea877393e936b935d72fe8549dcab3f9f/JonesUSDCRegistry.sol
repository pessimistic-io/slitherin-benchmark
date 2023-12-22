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

import { Require } from "./Require.sol";
import { OnlyDolomiteMargin } from "./OnlyDolomiteMargin.sol";
import { IERC4626 } from "./IERC4626.sol";
import { IJonesGLPAdapter } from "./IJonesGLPAdapter.sol";
import { IJonesGLPVaultRouter } from "./IJonesGLPVaultRouter.sol";
import { IJonesUSDCRegistry } from "./IJonesUSDCRegistry.sol";
import { IJonesWhitelistController } from "./IJonesWhitelistController.sol";


/**
 * @title   JonesUSDCRegistry
 * @author  Dolomite
 *
 * @notice  Implementation for a registry that contains all of the JonesDAO-related addresses. This registry is needed
 *          to offer uniform access to addresses in an effort to keep Dolomite's contracts as up-to-date as possible
 *          without having to deprecate the system and force users to migrate when Dolomite needs to point to new
 *          contracts or functions that JonesDAO introduces.
 */
contract JonesUSDCRegistry is IJonesUSDCRegistry, OnlyDolomiteMargin {

    // ==================== Constants ====================

    bytes32 private constant _FILE = "JonesUSDCRegistry";

    // ==================== Storage ====================

    IJonesGLPAdapter public override glpAdapter;
    IJonesGLPVaultRouter public override glpVaultRouter;
    IJonesWhitelistController public override whitelistController;
    IERC4626 public override usdcReceiptToken;
    IERC4626 public override jUSDC;
    address public override unwrapperTrader;

    // ==================== Constructor ====================

    constructor(
        address _glpAdapter,
        address _glpVaultRouter,
        address _whitelistController,
        address _usdcReceiptToken,
        address _jUSDC,
        address _dolomiteMargin
    )
    OnlyDolomiteMargin(
        _dolomiteMargin
    )
    {
        glpAdapter = IJonesGLPAdapter(_glpAdapter);
        glpVaultRouter = IJonesGLPVaultRouter(_glpVaultRouter);
        whitelistController = IJonesWhitelistController(_whitelistController);
        usdcReceiptToken = IERC4626(_usdcReceiptToken);
        jUSDC = IERC4626(_jUSDC);
    }

    function initializeUnwrapperTrader(
        address _unwrapperTrader
    ) external {
        Require.that(
            unwrapperTrader == address(0),
            _FILE,
            "Already initialized"
        );
        _setUnwrapperTrader(_unwrapperTrader);
    }

    function ownerGlpAdapter(
        address _glpAdapter
    )
    external
    onlyDolomiteMarginOwner(msg.sender) {
        Require.that(
            _glpAdapter != address(0),
            _FILE,
            "Invalid glpAdapter address"
        );
        glpAdapter = IJonesGLPAdapter(_glpAdapter);
        emit GlpAdapterSet(_glpAdapter);
    }

    function ownerSetGlpVaultRouter(
        address _glpVaultRouter
    )
    external
    onlyDolomiteMarginOwner(msg.sender) {
        Require.that(
            _glpVaultRouter != address(0),
            _FILE,
            "Invalid glpVaultRouter address"
        );
        glpVaultRouter = IJonesGLPVaultRouter(_glpVaultRouter);
        emit GlpVaultRouterSet(_glpVaultRouter);
    }

    function ownerSetWhitelistController(
        address _whitelistController
    )
    external
    onlyDolomiteMarginOwner(msg.sender) {
        Require.that(
            _whitelistController != address(0),
            _FILE,
            "Invalid whitelist address"
        );
        whitelistController = IJonesWhitelistController(_whitelistController);
        emit WhitelistControllerSet(_whitelistController);
    }

    function ownerSetUsdcReceiptToken(
        address _usdcReceiptToken
    )
    external
    onlyDolomiteMarginOwner(msg.sender) {
        Require.that(
            _usdcReceiptToken != address(0),
            _FILE,
            "Invalid usdcReceiptToken address"
        );
        usdcReceiptToken = IERC4626(_usdcReceiptToken);
        emit UsdcReceiptTokenSet(_usdcReceiptToken);
    }

    function ownerSetJUSDC(
        address _jUSDC
    )
    external
    onlyDolomiteMarginOwner(msg.sender) {
        Require.that(
            _jUSDC != address(0),
            _FILE,
            "Invalid jUSDC address"
        );
        jUSDC = IERC4626(_jUSDC);
        emit JUSDCSet(_jUSDC);
    }

    function ownerSetUnwrapperTrader(
        address _unwrapperTrader
    )
    external
    onlyDolomiteMarginOwner(msg.sender) {
        _setUnwrapperTrader(_unwrapperTrader);
    }

    // ==================== Private Functions ====================

    function _setUnwrapperTrader(address _unwrapperTrader) internal {
        Require.that(
            _unwrapperTrader != address(0),
            _FILE,
            "Invalid unwrapperTrader address"
        );
        unwrapperTrader = _unwrapperTrader;
        emit UnwrapperTraderSet(_unwrapperTrader);
    }
}

