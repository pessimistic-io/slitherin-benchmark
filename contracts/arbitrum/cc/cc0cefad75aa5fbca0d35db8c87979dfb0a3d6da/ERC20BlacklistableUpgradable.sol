// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "./Initializable.sol";
import {ERC20Upgradeable} from "./ERC20Upgradeable.sol";
import {BlacklistableUpgradable} from "./BlacklistableUpgradable.sol";

contract ERC20BlacklistableUpgradable is Initializable, ERC20Upgradeable, BlacklistableUpgradable {
    function __ERC20Blacklistable_init() internal onlyInitializing {
        __Blacklistable_init();
    }

    function __ERC20Blacklistable_init_unchained() internal onlyInitializing {}

    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override notBlacklisted(from) notBlacklisted(to) {
        super._update(from, to, value);
    }
}

