//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import { MemoryInterface, InstaMapping, ListInterface, InstaConnectors } from "./interfaces.sol";


abstract contract Stores {

  /**
   * @dev Return ethereum address
   */
  address constant internal ethAddr = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  /**
   * @dev Return Wrapped ETH address
   */
  address constant internal wethAddr = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

  /**
   * @dev Return memory variable address
   */
  MemoryInterface constant internal instaMemory = MemoryInterface(0x9c49adCf5D03005465fC906f73D27181A9214e80);

  /**
   * @dev Return InstaList address
   */
  ListInterface internal constant instaList = ListInterface(0x2E9D4A3C9565a3E826641B749Dd71297A450B77e);

  /**
   * @dev Return connectors registry address
   */
  InstaConnectors internal constant instaConnectors = InstaConnectors(0xfc09489b5daDaED2F272107295854609E66cD872);

  /**
   * @dev Get Uint value from InstaMemory Contract.
   */
  function getUint(uint getId, uint val) internal returns (uint returnVal) {
    returnVal = getId == 0 ? val : instaMemory.getUint(getId);
  }

  /**
  * @dev Set Uint value in InstaMemory Contract.
  */
  function setUint(uint setId, uint val) virtual internal {
    if (setId != 0) instaMemory.setUint(setId, val);
  }

}

