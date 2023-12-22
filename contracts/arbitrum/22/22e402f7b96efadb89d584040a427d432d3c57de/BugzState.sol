//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC20Upgradeable.sol";

import "./IBugz.sol";
import "./AdminableUpgradeable.sol";

abstract contract BugzState is Initializable, IBugz, ERC20Upgradeable, AdminableUpgradeable {

    function __BugzState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC20Upgradeable.__ERC20_init("Bugz", "$BUGZ");
    }
}
