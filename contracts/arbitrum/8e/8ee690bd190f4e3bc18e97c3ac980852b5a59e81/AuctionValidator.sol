// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;
// Is there a better MerkleProof library?
import "./MerkleProof.sol";
import "./IMintValidator.sol";
import "./IFabricator.sol";
// Replace with solmate auth? Maybe we make it ownable _by_ an auth instance
import "./Ownable.sol";

// note: add auth structure, needs to use a commit reveal pattern
/*
  We create a drop that will allow users to deposit funds in order to receive raffle tickets.
  At the end of the drop some of the people get a token, others don't.
*/
contract AuctionValidator is IMintValidator, Ownable {
  uint256 public depositCost = 8;
  struct Drop {
    uint256 collectibleId;
    uint128 quantityAvailable;
    uint64 startTime;
    uint64 endTime;
    // do we want a start block?
    uint64 endBlock;
    bytes32 acceptedBid;
  }

  mapping(uint256 => Drop) public drops;

  IFabricator public core;
  // Is it okay to have this universal? Do we need to bundle this into the drop struct?
  // We handle this by mapping a _hash_ of dropID and bidder
  mapping(bytes32 => uint256) public bids;

  constructor(IFabricator _core) {
    core = _core;
  }

  function getBid(uint256 _dropID, address bidder)
    external
    view
    returns (uint256)
  {
    bytes32 hashIndex = keccak256(abi.encodePacked(_dropID, bidder));
    return bids[hashIndex];
  }

  function addBid(uint256 _dropID, address bidder) external payable {
    Drop storage drop = drops[_dropID];
    require(
      msg.value > depositCost,
      "Sorry, that's not enough for the deposit"
    );
    // TODO: Consolidate these to save gas when we don't need seperate errors for testing?
    require(block.timestamp > drop.startTime, "SEQ_DROP_TIME_EARLY");
    require(block.timestamp <= drop.endTime, "SEQ_DROP_TIME_EXPIRED");
    require(block.number <= drop.endBlock, "SEQ_DROP_BLOCK_PASSED");
    // Use dropID + bidder to form primary key for bid
    bytes32 hashIndex = keccak256(abi.encodePacked(_dropID, bidder));
    bids[hashIndex] += msg.value;
    // Raffle tickets can only be acquired during the drop time

    // If the auction is close to ending extend it (fuck off frontrunners < 3)
    if (drop.endTime - block.timestamp < 300) {
      drop.endTime = 300;
    }
  }

  function setWinner(uint256 _dropID, address bidder) external onlyOwner {
    Drop storage drop = drops[_dropID];
    require(block.timestamp > drop.endTime, "SEQ_DROP_TIME_EARLY");
    require(drop.acceptedBid == 0, "Winner can only be set once");
    bytes32 hashIndex = keccak256(abi.encodePacked(_dropID, bidder));
    drop.acceptedBid = hashIndex;
  }

  function claimAuction(uint256 _dropID) external {
    _claimAuction(_dropID, msg.sender);
  }

  function validate(
    address _recipient,
    uint256 _dropID, /* _dropId*/
    uint256[] calldata, /* _qty*/
    string calldata, /* _metadata*/
    bytes memory /* _data*/
  ) external override {
    _claimAuction(_dropID, _recipient);
  }

  function _claimAuction(uint256 _dropID, address _recipient) internal {
    Drop memory drop = drops[_dropID];
    bytes32 hashIndex = keccak256(abi.encodePacked(_dropID, _recipient));
    uint256 minBid = bids[drop.acceptedBid];
    uint256 userBid = bids[hashIndex];
    require(
      userBid >= minBid,
      "Sorry your bid is not a winner bb, get ur weight up"
    );
    uint256[] memory idReturn = new uint256[](1);
    uint256[] memory quantityReturn = new uint256[](1);
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
  ) external {
    /*
     1. ?split startId in type and index
     2.
     */
    require(
      drops[_collectibleId].collectibleId == 0,
      "SEQ_DROP_DUPLICATE_DROP"
    );
    require(
      core.idToValidator(_collectibleId) == address(this),
      "Stop hitting yourself"
    );
    drops[_collectibleId] = Drop(
      _collectibleId,
      _quantityAvailable,
      _startTime,
      _endTime,
      _endBlock,
      0
    );
  }
}

