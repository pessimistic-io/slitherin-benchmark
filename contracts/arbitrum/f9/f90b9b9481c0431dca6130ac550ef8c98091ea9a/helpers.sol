//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import { DSMath } from "./math.sol";
import { Basic } from "./basic.sol";
import { ListInterface } from "./interface.sol";

abstract contract Helpers is DSMath, Basic {
    ListInterface internal constant listContract = ListInterface(0x2E9D4A3C9565a3E826641B749Dd71297A450B77e);

    function checkAuthCount() internal view returns (uint count) {
        uint64 accountId = listContract.accountID(address(this));
        count = listContract.accountLink(accountId).count;
    }
}
