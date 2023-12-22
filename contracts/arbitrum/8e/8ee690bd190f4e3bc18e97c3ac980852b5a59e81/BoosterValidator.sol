pragma solidity ^0.8.0;

import "./VRFConsumerBase.sol";
import "./Ownable.sol";
import "./IMintValidator.sol";
import "./IFabricator.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT WHICH USES HARDCODED VALUES FOR CLARITY.
 * PLEASE DO NOT USE THIS CODE IN PRODUCTION.
 */
contract BoosterValidator is VRFConsumerBase, Ownable, IMintValidator {
  struct Drop {
    uint256[] odds;
    uint256[] ids;
    address paymentToken;
    uint256 packCost;
    uint64 startTime;
    uint64 endTime;
    // do we want a start block?
    uint64 endBlock;
  }

  struct Request {
    uint256 dropID;
    uint256 quantity;
    address recipient;
  }

  bytes32 internal _keyHash;
  uint256 internal _fee;
  mapping(bytes32 => Request) public requests;
  mapping(uint256 => bool) public usedIds;
  mapping(uint256 => Drop) public drops;
  uint256 public dropCount;
  // initialize with token and track state there
  //mapping(uint256 => bool) public claimed;

  IFabricator public core;

  event RequestId(bytes32 requestId);

  /**
   * Constructor inherits VRFConsumerBase
   *
   * Network: Kovan
   * Chainlink VRF Coordinator address:  0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9
   * LINK token address:                 0xa36085F69e2889c224210F603D836748e7dC0088
   * Key Hash: 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4
   */
  constructor(
    IFabricator _core,
    address coordinator,
    address link
  )
    VRFConsumerBase(
      coordinator, // VRF Coordinator
      link // LINK Token
    )
  {
    _keyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4;
    _fee = 0; //0.1 * 10**18; // 0.1 LINK (Varies by network)
    core = _core;
  }

  /**
   * Requests randomness from a user-provided seed
   */
  function getRandomNumber() public returns (bytes32 requestId) {
    require(_link.balanceOf(address(this)) >= _fee, "BOOST_LINK_BALLANCE_LOW");
    return _requestRandomness(_keyHash, _fee);
  }

  /**
   * Callback function used by VRF Coordinator
   */
  function _fulfillRandomness(bytes32 requestId, uint256 randomness)
    internal
    override
  {
    Drop memory drop = drops[requests[requestId].dropID];
    uint256[] memory odds = drop.odds;
    uint256[] memory idReturn = new uint256[](1);
    uint256[] memory quantityReturn = new uint256[](1);
    uint256 totalOdds;
    uint256 currentChance = odds[0];
    for (uint256 i = 0; i < odds.length; i++) {
      totalOdds += odds[i];
    }
    uint256 randomResult = randomness % totalOdds;
    uint256 j = 0;
    for (j; currentChance < randomResult; j++) {
      currentChance += odds[j];
    }
    idReturn[0] = drop.ids[j];
    quantityReturn[0] = requests[requestId].quantity;
    core.modularMintCallback(
      requests[requestId].recipient,
      idReturn,
      quantityReturn,
      ""
    );
  }

  // function withdrawLink() external {} - Implement a withdraw function to avoid locking your LINK in the contract

  function validate(
    address recipient,
    uint256 _dropID, /* _dropId*/
    uint256[] memory _requestedAmounts, /* _qty*/
    string calldata, /* _metadata*/
    bytes memory /* _data*/
  ) external override {
    Drop memory drop = drops[_dropID];
    // 0. validate that blocknumber or timestamp have not passed
    require(block.timestamp > drop.startTime, "BOOST_DROP_TIME_EARLY");
    require(block.timestamp <= drop.endTime, "BOOST_DROP_TIME_EXPIRED_Poop");
    require(block.number <= drop.endBlock, "BOOST_DROP_BLOCK_PASSED");
    // 2. validate that the indicated quantity is available
    require(_requestedAmounts.length == 1, "BOOST_DROP_REQUEST_AMOUNTS_LENGTH");
    bytes32 requestId = getRandomNumber();
    requests[requestId] = Request(_dropID, _requestedAmounts[0], recipient);
    emit RequestId(requestId);
  }

  function createDrop(
    uint256[] memory _collectibleIds,
    uint256[] memory _odds,
    address _paymentToken,
    uint256 _packCost,
    uint64 _startTime,
    uint64 _endTime,
    uint16 _endBlock
  ) external onlyOwner {
    /*
   1. ?split startId in type and index
   2.
   */
    for (uint256 i; i < _collectibleIds.length; i++) {
      require(!usedIds[_collectibleIds[i]], "BOOST_DROP_DUPLICATE_DROP");
      usedIds[_collectibleIds[i]] = true;
    }
    drops[dropCount] = Drop(
      _odds,
      _collectibleIds,
      _paymentToken,
      _packCost,
      _startTime,
      _endTime,
      _endBlock
    );
    dropCount += 1;
    // Log a drop created event with some tangible identifiers to latch onto
  }

  function getDropIds(uint256 drop) external view returns (uint256[] memory) {
    return drops[drop].ids;
  }

  function getDropOdds(uint256 drop) external view returns (uint256[] memory) {
    return drops[drop].odds;
  }
}

