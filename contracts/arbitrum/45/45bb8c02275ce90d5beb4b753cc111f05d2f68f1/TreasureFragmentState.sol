//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ERC1155HybridUpgradeable.sol";
import "./ITreasureFragment.sol";

abstract contract TreasureFragmentState is Initializable, ERC1155HybridUpgradeable {

    function __TreasureFragmentState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155HybridUpgradeable.__ERC1155Hybrid_init();
    }
}
