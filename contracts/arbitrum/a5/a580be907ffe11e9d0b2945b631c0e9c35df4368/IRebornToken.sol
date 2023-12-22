// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {IERC20PermitUpgradeable} from "./draft-IERC20PermitUpgradeable.sol";

interface IRebornTokenDef {
    /// @dev revert when the caller is not minter
    error NotMinter();
    /// @dev disable upgrade
    error CannotUpgradeAnyMore();
    /// @dev emit when minter is updated
    event MinterUpdate(address minter, bool valid);
}

interface IRebornToken is
    IERC20Upgradeable,
    IERC20PermitUpgradeable,
    IRebornTokenDef
{
    function mint(address to, uint256 amount) external;
}

