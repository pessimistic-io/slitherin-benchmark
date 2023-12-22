// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;

import "./MerkleProof.sol";
import "./Ownable.sol";
import "./IMintValidator.sol";
import "./IFabricator.sol";

contract SequenceValidator is Ownable, IMintValidator {
  struct Drop {
    uint256 collectibleId;
    uint128 quantityAvailable;
    uint64 startTime;
    uint64 endTime;
    // do we want a start block?
    uint64 endBlock;
  }

  mapping(uint256 => Drop) public drops;
  // initialize with token and track state there
  //mapping(uint256 => bool) public claimed;
  // This should really be an interface
  IFabricator public core;

  constructor(IFabricator _core) {
    core = _core;
  }

  function validate(
    address _recipient,
    uint256 _dropID, /* _dropId*/
    uint256[] calldata quantity, /* _qty*/
    string calldata, /* _metadata*/
    bytes memory /* _data*/
  ) external override {
    Drop memory drop = drops[_dropID];
    uint256[] memory idReturn = new uint256[](1);
    uint256[] memory quantityReturn = new uint256[](1);
    // 0. validate that blocknumber or timestamp have not passed
    require(block.timestamp > drop.startTime, "SEQ_DROP_TIME_EARLY");
    require(block.timestamp <= drop.endTime, "SEQ_DROP_TIME_EXPIRED");
    require(block.number <= drop.endBlock, "SEQ_DROP_BLOCK_PASSED");
    // 2. validate that the indicated quantity is available
    require(
      core.quantityMinted(drop.collectibleId) + quantity[0] <=
        drop.quantityAvailable,
      "SEQ_DROP_MAX_QUANTITY"
    );
    require(quantity[0] == 1, "SEQ_DROP_LIMIT_ONE");

    // 3. Call Callback Mint Function
    idReturn[0] = drop.collectibleId;
    quantityReturn[0] = 1;
    core.modularMintCallback(_recipient, idReturn, quantityReturn, "");
  }

  function createDrop(
    uint256 _collectibleId,
    uint16 _quantityAvailable,
    uint64 _startTime,
    uint64 _endTime,
    uint16 _endBlock
  ) external onlyOwner {
    /*
     1. ?split startId in type and index
     2.
     */
    require(
      drops[_collectibleId].collectibleId == 0,
      "SEQ_DROP_DUPLICATE_DROP"
    );
    drops[_collectibleId] = Drop(
      _collectibleId,
      _quantityAvailable,
      _startTime,
      _endTime,
      _endBlock
    );
  }
}

