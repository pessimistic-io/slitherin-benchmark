// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;

import "./MerkleProof.sol";
import "./Ownable.sol";
import "./IMintValidator.sol";

contract MerkleValidator is Ownable, IMintValidator {
  struct Drop {
    bytes32 _merkleRoot;
    uint16 _blocks;
    uint64 _endTime;
  }

  mapping(uint256 => Drop) public drops;
  mapping(uint256 => bool) public claimed;

  // This is a pull only pattern?
  function validate(
    address, /* _operator*/
    uint256, /* _dropId*/
    uint256[] memory, /*_requestedQty*/
    string calldata, /*  _metadata*/
    bytes memory /* _data*/
  ) external pure override {
    // 0: validate that blocknumber or timestamp have not passed
    // 1. lookup merkle root and ensure drop is valid
    // 2. generate hash using input params
    // 3. verify hash
    // 4. mark as claimed? probably better to check this on the token contract
    // 5. Trigger callback function
  }

  function seedAllocations(
    uint256 _dropKey,
    bytes32 _merkleRoot,
    uint16 _blocks,
    uint64 _endTime
  ) external onlyOwner {
    require(drops[_dropKey]._merkleRoot == bytes32(0), "cannot rewrite a drop");
    drops[_dropKey] = Drop(_merkleRoot, _blocks, _endTime);
  }
}

