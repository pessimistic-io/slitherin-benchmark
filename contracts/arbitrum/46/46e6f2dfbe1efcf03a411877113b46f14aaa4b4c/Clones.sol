// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (proxy/Clones.sol)

pragma solidity ^0.8.0;

/**
 * @dev https://eips.ethereum.org/EIPS/eip-1167[EIP 1167] is a standard for
 * deploying minimal proxy contracts, also known as "clones".
 *
 * > To simply and cheaply clone contract functionality in an immutable way, this standard specifies
 * > a minimal bytecode implementation that delegates all calls to a known, fixed address.
 *
 * The library includes functions to deploy a proxy using either `create` (traditional deployment) or `create2`
 * (salted deterministic deployment). It also includes functions to predict the addresses of clones deployed using the
 * deterministic method.
 *
 * _Available since v3.4._
 */
library Clones {
  /**
   * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
   *
   * This function uses the create opcode, which should never revert.
   */
  function clone(address implementation) internal returns (address instance) {
    /// @solidity memory-safe-assembly
    assembly {
      let ptr := mload(0x40)
      mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
      mstore(add(ptr, 0x14), shl(0x60, implementation))
      mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
      instance := create(0, ptr, 0x37)
    }
    require(instance != address(0), "ERC1167: create failed");
  }

  /**
   * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
   *
   * This function uses the create2 opcode and a `salt` to deterministically deploy
   * the clone. Using the same `implementation` and `salt` multiple time will revert, since
   * the clones cannot be deployed twice at the same address.
   */
  function cloneDeterministic(address implementation, bytes32 salt) internal returns (address instance) {
    /// @solidity memory-safe-assembly
    assembly {
      let ptr := mload(0x40)
      mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
      mstore(add(ptr, 0x14), shl(0x60, implementation))
      mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
      instance := create2(0, ptr, 0x37, salt)
    }
    require(instance != address(0), "ERC1167: create2 failed");
  }

  /**
   * @dev Computes the address of a clone deployed using {Clones-cloneDeterministic}.
   */
  function predictDeterministicAddress(
    address implementation,
    bytes32 salt,
    address deployer
  ) internal pure returns (address predicted) {
    /// @solidity memory-safe-assembly
    assembly {
      let ptr := mload(0x40)
      mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
      mstore(add(ptr, 0x14), shl(0x60, implementation))
      mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf3ff00000000000000000000000000000000)
      mstore(add(ptr, 0x38), shl(0x60, deployer))
      mstore(add(ptr, 0x4c), salt)
      mstore(add(ptr, 0x6c), keccak256(ptr, 0x37))
      predicted := keccak256(add(ptr, 0x37), 0x55)
    }
  }

  /**
   * @dev Computes the address of a clone deployed using {Clones-cloneDeterministic}.
   */
  function predictDeterministicAddress(address implementation, bytes32 salt)
    internal
    view
    returns (address predicted)
  {
    return predictDeterministicAddress(implementation, salt, address(this));
  }

  // from https://github.com/optionality/clone-factory
  function isClone(address target, address query)
    internal
    view
    returns (bool result)
  {
    bytes20 targetBytes = bytes20(target);
    assembly {
      // load the next free memory slot as a place to store the comparison clone
      let ptr := mload(0x40)

      // The next three lines store the expected bytecode for a miniml proxy
      // that targets `target` as its implementation contract
      mstore(
        ptr,
        0x363d3d373d3d3d363d7300000000000000000000000000000000000000000000
      )
      mstore(add(ptr, 0xa), targetBytes)
      mstore(
        add(ptr, 0x1e),
        0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
      )

      // the next two lines store the bytecode of the contract that we are checking in memory
      let other := add(ptr, 0x40)
      extcodecopy(query, other, 0, 0x2d)

      // Check if the expected bytecode equals the actual bytecode and return the result
      result := and(
        eq(mload(ptr), mload(other)),
        eq(mload(add(ptr, 0xd)), mload(add(other, 0xd)))
      )
    }
  }
}

