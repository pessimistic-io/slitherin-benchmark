//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC1155BurnableUpgradeable.sol";
import "./Initializable.sol";

import "./AdminableUpgradeable.sol";

abstract contract SmolTreasuresState is Initializable, AdminableUpgradeable, ERC1155BurnableUpgradeable {

    function __SmolTreasuresState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155BurnableUpgradeable.__ERC1155Burnable_init();
        // TODO: Set URI.
        ERC1155Upgradeable.__ERC1155_init_unchained("");
    }
}
