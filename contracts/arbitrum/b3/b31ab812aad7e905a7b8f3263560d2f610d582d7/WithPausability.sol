// Neptune Mutual Protocol (https://neptunemutual.com)
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Pausable.sol";
import "./Ownable.sol";

abstract contract WithPausability is Pausable, Ownable {
  /**
   * @dev Pauses or unpauses this contract.
   */
  function pause(bool flag) external onlyOwner {
    if (flag) {
      super._pause();
      return;
    }

    super._unpause();
  }
}

