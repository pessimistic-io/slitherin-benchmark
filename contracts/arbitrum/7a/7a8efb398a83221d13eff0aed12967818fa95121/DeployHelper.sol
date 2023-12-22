// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Strings} from "./Strings.sol";

library DeployHelper {
	 function toString(
      address addr) public pure returns (
      string memory) {
        return Strings.toHexString(uint160(addr), 20);
    }
}

