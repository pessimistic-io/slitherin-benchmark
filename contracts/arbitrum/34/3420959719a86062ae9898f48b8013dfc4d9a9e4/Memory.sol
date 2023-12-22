// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

library Memory {
  function writeUint256ToMemory(uint256 _input) internal pure {
    assembly {
      let freeMemoryPointer := mload(0x40)
      mstore(freeMemoryPointer, _input)
      let nextAvailableMemory := add(mload(0x40), 0x20)
      mstore(0x40, nextAvailableMemory)
    }
  }

  function readUint256FromMemory(bytes32 offset) internal pure returns (uint256 result) {
    assembly {
      result := mload(offset)
    }
  }

  function updateUint256InMemory(bytes32 offset, uint256 _input) internal pure {
    assembly {
      mstore(offset, _input)
    }
  }

  function getFreeMemoryPointer() internal pure returns (uint256 pointer) {
    assembly {
      pointer := mload(0x40)
    }
  }

  function jumpFreeMemoryPointer(bytes32 offset) internal pure {
    assembly {
      mstore(0x40, add(mload(0x40), offset))
    }
  }
}

