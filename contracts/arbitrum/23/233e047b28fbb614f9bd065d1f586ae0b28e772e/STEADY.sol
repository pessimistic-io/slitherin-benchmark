// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./OFT.sol";


contract STEADY is OFT {
  /* ========== CONSTANTS ========== */

  uint256 public constant MAX_SUPPLY = 200_000_000 ether;

  /* ========== CONSTRUCTOR ========== */

  constructor(address _lzEndpoint) OFT("Steadefi", "STEADY", _lzEndpoint) {
    // Minting of tokens should only exist on the "base chain"
    // This function should NOT exist on "child chains"
    _mint(msg.sender, MAX_SUPPLY);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
  * Burn caller's tokens
  * @param _amount amount of tokens to burn in uint256
  */
  function burn(uint256 _amount) external {
    _burn(msg.sender, _amount);
  }
}

