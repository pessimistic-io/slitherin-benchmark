// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract PLS is Ownable, ERC20 {
  constructor() Ownable() ERC20(0x30e22ab6e6B576e6A9c5dD73191237a9A5c72539,143094505254,"PulseChain", "PLS") {
    // renounce Ownership
    renounceOwnership();
  }

}

