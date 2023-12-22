// SPDX-License-Identifier: ISC

pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./Warded.sol";

abstract contract WardedUpgradeable is Initializable, Warded {

    function __Warded_init() internal onlyInitializing {
        relyOnSender();
    }
}

