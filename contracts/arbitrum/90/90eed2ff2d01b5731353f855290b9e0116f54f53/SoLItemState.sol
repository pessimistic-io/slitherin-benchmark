//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155Upgradeable.sol";

import "./ISoLItem.sol";
import "./AdminableUpgradeable.sol";

abstract contract SoLItemState is Initializable, ISoLItem, ERC1155Upgradeable, AdminableUpgradeable {

    function __SoLItemState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155Upgradeable.__ERC1155_init("");
    }
}
