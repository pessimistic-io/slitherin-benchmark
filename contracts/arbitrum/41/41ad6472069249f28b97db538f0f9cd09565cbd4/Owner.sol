// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

abstract contract Owner {
  /**
   * @dev bytes32(uint256(keccak256('eip1967.FRACT10N.owner')) - 1)
   */
  bytes32 constant _ownerSlot = 0x09f0f4aad16401d8d9fa2f59a36c61cf8593c814849bbc8ef7ed5c0c63e0e28f;

  modifier onlyOwner() {
    require(msg.sender == getOwner(), "FRACT10N: owner only function");
    _;
  }

  constructor() {}

  function owner() public view returns (address) {
    return getOwner();
  }

  function getOwner() public view returns (address ownerAddress) {
    assembly {
      ownerAddress := sload(_ownerSlot)
    }
  }

  function setOwner(address ownerAddress) public onlyOwner {
    assembly {
      sstore(_ownerSlot, ownerAddress)
    }
  }

  function ownerCall(address target, bytes calldata data) external payable onlyOwner {
    assembly {
      calldatacopy(0, data.offset, data.length)
      let result := call(gas(), target, callvalue(), 0, data.length, 0, 0)
      returndatacopy(0, 0, returndatasize())
      switch result
      case 0 {
        revert(0, returndatasize())
      }
      default {
        return(0, returndatasize())
      }
    }
  }

  function ownerDelegateCall(address target, bytes calldata data) external payable onlyOwner {
    assembly {
      calldatacopy(0, data.offset, data.length)
      let result := delegatecall(gas(), target, 0, data.length, 0, 0)
      returndatacopy(0, 0, returndatasize())
      switch result
      case 0 {
        revert(0, returndatasize())
      }
      default {
        return(0, returndatasize())
      }
    }
  }

  function ownerStaticCall(address target, bytes calldata data) external view onlyOwner {
    assembly {
      calldatacopy(0, data.offset, data.length)
      let result := staticcall(gas(), target, 0, data.length, 0, 0)
      returndatacopy(0, 0, returndatasize())
      switch result
      case 0 {
        revert(0, returndatasize())
      }
      default {
        return(0, returndatasize())
      }
    }
  }
}

