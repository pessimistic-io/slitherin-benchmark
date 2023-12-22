// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./Base.sol";

contract Slots is Base, VRFConsumerBaseV2 {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /* Chainlink VRF Variables */
  VRFCoordinatorV2Interface internal immutable i_vrfCOORDINATOR;
  bytes32 internal immutable i_gasLane;
  uint64 internal immutable i_subscriptionId;
  uint16 internal constant i_minimumRequestConfirmations = 3;
  uint32 internal immutable i_callbackGasLimit;

  event Slots_Play_Event(
    address indexed playerAddress,
    uint256 wager,
    address tokenAddress,
    uint256 numGames,
    int256 targetGain,
    int256 targetLoss,
    uint256 VRFFee
  );

  event Slots_Refund_Event(address indexed player, uint256 wager, address tokenAddress);
  event Received(address sender, uint256 value);
  event Slots_Outcome_Event(
    address indexed playerAddress,
    uint256 wager,
    uint256 payout,
    address tokenAddress,
    uint16[] slotIDs,
    uint256[] multipliers,
    uint256[] payouts,
    uint32 numGames
  );

  struct SlotsGameSessions {
    uint256 wager;
    uint256 requestId;
    address tokenAddress;
    uint64 blockNumber;
    uint32 numberOfBets;
    int256 targetGain;
    int256 targetLoss;
  }

  mapping(address => SlotsGameSessions) slotsGames;
  mapping(uint256 => address) slotsIDs;

  constructor(
    address _bankroll,
    address VRFCoordinatorV2,
    address link_feed,
    bytes32 _keyHash,
    uint64 _subscriptionId,
    uint32 _callBackGasLimit,
    uint16[] memory _multipliers,
    uint16[] memory _outcomeNum,
    uint16 _numOutcomes
  ) VRFConsumerBaseV2(VRFCoordinatorV2) {
    Bankroll = IBankroll(_bankroll);
    i_vrfCOORDINATOR = VRFCoordinatorV2Interface(VRFCoordinatorV2);
    linkPriceFeed = AggregatorV3Interface(link_feed);
    IChainLinkVRF = IVRFCoordinatorV2(VRFCoordinatorV2);
    i_gasLane = _keyHash;
    i_subscriptionId = _subscriptionId;
    i_callbackGasLimit = _callBackGasLimit;
    _setSlotsMultipliers(_multipliers, _outcomeNum, _numOutcomes);
  }

  mapping(uint16 => uint16) slotsMultipliers;
  uint16 numOutcomes;

  int256 constant EMPTY_VALUE = type(int256).max;

  function getSlotsSession(address player) external view returns (SlotsGameSessions memory) {
    return (slotsGames[player]);
  }

  function playSlots(
    uint256 wager,
    address tokenAddress,
    uint32 numberOfBets,
    int256 targetGain,
    int256 targetLoss
  ) external payable nonReentrant {
    require(!Bankroll.getStoppedStatus(), "Bankroll not active");
    require(Bankroll.getIsValidWager(address(this), tokenAddress), "invalid wager contract address");

    if (targetGain == 0) {
      targetGain = type(int256).max;
    }
    if (targetLoss == 0) {
      targetLoss = type(int256).max;
    }

    require(slotsGames[msg.sender].requestId == 0, "AwaitingVRF: player has an ongoing game");
    require(numberOfBets > 0 && numberOfBets <= 20, "InvalidNumBets: numberOfBets must be between 1 and 20");

    uint256 totalWager = wager.mul(numberOfBets);
    uint256 fee = _transferWager(tokenAddress, totalWager, 800000, 24);

    uint256 id = _requestRandomWords(numberOfBets);

    slotsGames[msg.sender] = SlotsGameSessions(
      wager,
      id,
      tokenAddress,
      uint64(block.number),
      numberOfBets,
      targetGain,
      targetLoss
    );
    slotsIDs[id] = msg.sender;

    emit Slots_Play_Event(msg.sender, wager, tokenAddress, numberOfBets, targetGain, targetLoss, fee);
  }

  function Slots_Refund() external nonReentrant {
    SlotsGameSessions storage game = slotsGames[msg.sender];
    require(game.requestId != 0, "no awaiting vrf");

    require(game.blockNumber + 200 > block.number, "blocknumber too low");
    uint256 wager = game.wager * game.numberOfBets;
    address tokenAddress = game.tokenAddress;

    delete (slotsIDs[game.requestId]);
    delete (slotsGames[msg.sender]);

    if (tokenAddress == address(0)) {
      (bool success, ) = payable(msg.sender).call{value: wager}("");
      require(success, "refund failed");
    } else {
      IERC20(tokenAddress).safeTransfer(msg.sender, wager);
    }
    emit Slots_Refund_Event(msg.sender, wager, tokenAddress);
  }

  /**
   * @dev Requests a certain number of random words from the Chainlink VRF.
   * @param numWords The number of random words to request from the VRF.
   * @return requestId The unique ID of the random word request, which can be used to retrieve the response.
   */
  function _requestRandomWords(uint32 numWords) internal returns (uint256 requestId) {
    requestId = i_vrfCOORDINATOR.requestRandomWords(
      i_gasLane,
      i_subscriptionId,
      i_minimumRequestConfirmations,
      i_callbackGasLimit,
      numWords
    );
  }

  function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external override {
    if (msg.sender != address(i_vrfCOORDINATOR)) {
      revert OnlyCoordinatorCanFulfill(msg.sender, address(i_vrfCOORDINATOR));
    }
    fulfillRandomWords(requestId, randomWords);
  }

  function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
    address playerAddress = slotsIDs[requestId];
    if (playerAddress == address(0)) revert();

    SlotsGameSessions storage game = slotsGames[playerAddress];

    uint256[] memory payouts = new uint256[](game.numberOfBets);
    uint16[] memory slotID = new uint16[](game.numberOfBets);
    uint256[] memory multipliers = new uint256[](game.numberOfBets);
    uint32 i;
    int256 totalValue;
    uint256 payout;

    address tokenAddress = game.tokenAddress;

    for (i = 0; i < game.numberOfBets; i++) {
      if (totalValue >= int256(game.targetGain)) {
        break;
      }
      if (totalValue <= -int256(game.targetLoss)) {
        break;
      }

      slotID[i] = uint16(randomWords[i] % numOutcomes);
      multipliers[i] = slotsMultipliers[slotID[i]];

      if (multipliers[i] != 0) {
        totalValue += int256(game.wager * multipliers[i]) - int256(game.wager);
        payout += game.wager * multipliers[i];
        payouts[i] = game.wager * multipliers[i];
      } else {
        totalValue -= int256(game.wager);
      }
    }

    payout += (game.numberOfBets - i) * game.wager;

    emit Slots_Outcome_Event(playerAddress, game.wager, payout, tokenAddress, slotID, multipliers, payouts, i);

    _transferToBankroll(game.wager * game.numberOfBets, tokenAddress);
    delete (slotsIDs[requestId]);
    delete (slotsGames[playerAddress]);
    if (payout != 0) {
      _transferPayout(playerAddress, payout, tokenAddress);
    }
  }

  function getSlotsMultipliers() external view returns (uint16[] memory multipliers) {
    multipliers = new uint16[](numOutcomes);
    for (uint16 i = 0; i < numOutcomes; i++) {
      multipliers[i] = slotsMultipliers[i];
    }
    return multipliers;
  }

  function _setSlotsMultipliers(
    uint16[] memory _multipliers,
    uint16[] memory _outcomeNum,
    uint16 _numOutcomes
  ) internal {
    for (uint16 i = 0; i < _numOutcomes; i++) {
      delete (slotsMultipliers[i]);
    }

    numOutcomes = _numOutcomes;

    for (uint16 i = 0; i < _multipliers.length; i++) {
      slotsMultipliers[_outcomeNum[i]] = _multipliers[i];
    }
  }

  function _kellyWager(uint256 wager, address tokenAddress) internal view {
    uint256 balance;

    if (tokenAddress == address(0)) {
      balance = address(Bankroll).balance;
    } else {
      balance = IERC20(tokenAddress).balanceOf(address(Bankroll));
    }
    uint256 maxWager = (balance * 55770) / 100000000; // 0.0577%
    // uint256 maxWager = (balance * 5577000) / 100000000; // 5.577%
    require(wager < maxWager, "Wager above limit");
  }

  receive() external payable {
    emit Received(msg.sender, msg.value);
  }

  fallback() external payable {}
}

