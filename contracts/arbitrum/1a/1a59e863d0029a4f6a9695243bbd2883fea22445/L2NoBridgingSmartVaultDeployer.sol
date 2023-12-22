// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.0;

import "./UncheckedMath.sol";
import "./IRegistry.sol";
import "./SmartVault.sol";
import "./Deployer.sol";
import "./Arrays.sol";
import "./PermissionsHelpers.sol";
import "./PermissionsManager.sol";

import "./BaseSmartVaultDeployer.sol";
import "./ParaswapSwapper.sol";

// solhint-disable avoid-low-level-calls

contract L2NoBridgingSmartVaultDeployer is BaseSmartVaultDeployer {
    using UncheckedMath for uint256;
    using PermissionsHelpers for PermissionsManager;

    struct Params {
        address[] owners;
        IRegistry registry;
        PermissionsManager manager;
        Deployer.SmartVaultParams smartVaultParams;
        SwapperActionParams paraswapSwapperActionParams;
    }

    constructor(address owner) BaseSmartVaultDeployer(owner) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function deploy(Params memory params) external onlyOwner {
        SmartVault smartVault = Deployer.createSmartVault(params.registry, params.manager, params.smartVaultParams);
        _setupSwapper(smartVault, params.manager, params.paraswapSwapperActionParams, ParaswapSwapper.call.selector);
        Deployer.transferPermissionManagerControl(params.manager, params.owners);
    }
}

