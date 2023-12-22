// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

abstract contract NonReentrant {
  /**
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.reentrant')) - 1)
   */
  bytes32 constant _reentrantSlot = 0x8f0a4f18077687341390ab92c27af2200503af695de18cbc999e7f3f59cf890b;

  modifier nonReentrant() {
    require(getStatus() != 2, "FRACT10N: reentrant call");
    setStatus(2);
    _;
    setStatus(1);
  }

  constructor() {}

  function getStatus() internal view returns (uint256 status) {
    assembly {
      status := sload(_reentrantSlot)
    }
  }

  function setStatus(uint256 status) internal {
    assembly {
      sstore(_reentrantSlot, status)
    }
  }
}

