//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC1155BurnableUpgradeable.sol";
import "./Initializable.sol";

import "./AdminableUpgradeable.sol";
import "./IConsumable.sol";

abstract contract ConsumableState is Initializable, AdminableUpgradeable, ERC1155BurnableUpgradeable {

    string internal baseURI;

    function __ConsumableState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155BurnableUpgradeable.__ERC1155Burnable_init();
        ERC1155Upgradeable.__ERC1155_init_unchained("");
    }
}
