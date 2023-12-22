//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ITreasureFragment.sol";
import "./IFragmentSwapper.sol";
import "./AdminableUpgradeable.sol";

abstract contract FragmentSwapperState is Initializable, IFragmentSwapper, AdminableUpgradeable {

    ITreasureFragment public treasureFragment;

    function __FragmentSwapperState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
    }
}
