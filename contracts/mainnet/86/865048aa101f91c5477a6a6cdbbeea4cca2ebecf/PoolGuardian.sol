// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "./TitanProxy.sol";
import "./PoolStorage.sol";

contract PoolGuardian is TitanProxy, PoolStorage {
    constructor(
        address _SAVIOR,
        address _implementation,
        address _shorterBone
    ) public TitanProxy(_SAVIOR, _implementation) {
        shorterBone = IShorterBone(_shorterBone);
    }
}

