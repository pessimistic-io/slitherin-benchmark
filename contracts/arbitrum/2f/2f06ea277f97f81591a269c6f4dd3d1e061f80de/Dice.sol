// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./Base.sol";

contract Dice is Base, VRFConsumerBaseV2 {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /* Chainlink VRF Variables */
  VRFCoordinatorV2Interface internal immutable i_vrfCOORDINATOR;
  bytes32 internal immutable i_gasLane;
  uint64 internal immutable i_subscriptionId;
  uint16 internal constant i_minimumRequestConfirmations = 3;
  uint32 internal immutable i_callbackGasLimit;

  // events
  event Dice_Outcome_Event(
    address indexed playerAddress,
    uint256 wager,
    uint256 payout,
    address tokenAddress,
    uint32 multiplier,
    bool isOver,
    uint256[] diceGameOutcomes,
    uint256[] payouts,
    uint256 numGames
  );
  event Dice_Refund_Event(address indexed player, uint256 wager, address tokenAddress);
  event Received(address sender, uint256 value);
  event Dice_Play_Event(
    address indexed playerAddress,
    uint256 wager,
    uint32 multiplier,
    address tokenAddress,
    bool isOver,
    uint32 numBets,
    int256 targetGain,
    int256 targetLoss,
    uint256 VRFFee
  );

  struct GameSession {
    address player;
    uint256 wager;
    uint256 requestId;
    address tokenAddress;
    uint64 blockNumber;
    uint32 numberOfBets;
    uint32 multiplier;
    int256 targetGain;
    int256 targetLoss;
    bool isOver;
    uint256 timestamp;
  }

  mapping(address => GameSession) sessions;
  mapping(uint256 => address) private s_results;

  constructor(
    address _bankroll,
    address VRFCoordinatorV2,
    address link_feed,
    bytes32 _keyHash,
    uint64 _subscriptionId,
    uint32 _callBackGasLimit
  ) VRFConsumerBaseV2(VRFCoordinatorV2) {
    Bankroll = IBankroll(_bankroll);
    i_vrfCOORDINATOR = VRFCoordinatorV2Interface(VRFCoordinatorV2);
    linkPriceFeed = AggregatorV3Interface(link_feed);
    IChainLinkVRF = IVRFCoordinatorV2(VRFCoordinatorV2);
    i_gasLane = _keyHash;
    i_subscriptionId = _subscriptionId;
    i_callbackGasLimit = _callBackGasLimit;
  }

  int256 constant EMPTY_VALUE = type(int256).max;

  function getDiceSessionResults(uint256 reqId) external view returns (address player) {
    return s_results[reqId];
  }

  function playDice(
    uint256 wagerAmount,
    uint32 multiplier,
    uint32 numberOfBets,
    int256 targetGain,
    int256 targetLoss,
    bool isOver,
    address tokenAddress
  ) external payable nonReentrant {
    require(!Bankroll.getStoppedStatus(), "Bankroll not active");
    require(Bankroll.getIsValidWager(address(this), tokenAddress), "set valid wager to begin");
    if (targetGain == 0) {
      targetGain = type(int256).max;
    }
    if (targetLoss == 0) {
      targetLoss = type(int256).max;
    }

    require(
      multiplier >= 11000 && multiplier <= 9900000,
      "InvalidMultiplier: Multiplier must be between 11000 and 9900000"
    );
    require(sessions[msg.sender].requestId == 0, "AwaitingVRF: player has an ongoing game");
    require(numberOfBets > 0 && numberOfBets <= 20, "InvalidNumBets: numberOfBets must be between 1 and 20");

    _kellyWager(wagerAmount, tokenAddress, multiplier);
    uint256 totalWager = wagerAmount.mul(numberOfBets);
    uint256 fee = _transferWager(tokenAddress, totalWager, 800000, 22);

    uint256 requestID = _requestRandomWords(numberOfBets);

    sessions[msg.sender] = GameSession(
      msg.sender,
      wagerAmount,
      requestID,
      tokenAddress,
      uint64(block.number),
      numberOfBets,
      multiplier,
      targetGain,
      targetLoss,
      isOver,
      block.timestamp
    );

    s_results[requestID] = msg.sender;

    emit Dice_Play_Event(
      msg.sender,
      wagerAmount,
      multiplier,
      tokenAddress,
      isOver,
      numberOfBets,
      targetGain,
      targetLoss,
      fee
    );
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
    address playerAddress = s_results[requestId];
    require(playerAddress != address(0), "Invalid Address");
    GameSession storage game = sessions[playerAddress];

    int256 totalAmount;
    uint256 payout;
    uint256 i;
    uint256[] memory gameOutcomes = new uint256[](game.numberOfBets);
    uint256[] memory payouts = new uint256[](game.numberOfBets);

    uint256 winningProbability = 99000000000 / game.multiplier;
    uint256 rollOverThreshold = 10000000 - winningProbability;
    uint256 gameReward = ((game.multiplier * game.wager) / 10000);

    require(gameReward >= game.wager, "Game reward underflow");

    address tokenAddress = game.tokenAddress;

    for (i = 0; i < game.numberOfBets; i++) {
      if (totalAmount >= int256(game.targetGain) || totalAmount <= -int256(game.targetLoss)) {
        break;
      }

      gameOutcomes[i] = randomWords[i] % 10000000;

      if ((gameOutcomes[i] >= rollOverThreshold && game.isOver == true)) {
        totalAmount += int256(gameReward - game.wager);
        payout += gameReward;
        payouts[i] = gameReward;
        continue;
      }

      if (gameOutcomes[i] <= winningProbability && game.isOver == false) {
        totalAmount += int256(gameReward - game.wager);
        payout += gameReward;
        payouts[i] = gameReward;
        continue;
      }

      totalAmount = totalAmount - int256(game.wager);
    }

    payout += (game.numberOfBets - i) * game.wager;

    emit Dice_Outcome_Event(
      playerAddress,
      game.wager,
      payout,
      tokenAddress,
      game.multiplier,
      game.isOver,
      gameOutcomes,
      payouts,
      i
    );

    _transferToBankroll(game.wager * game.numberOfBets, tokenAddress);

    delete (s_results[requestId]);
    delete (sessions[playerAddress]);

    if (payout != 0) {
      _transferPayout(playerAddress, payout, tokenAddress);
    }
  }

  function _kellyWager(uint256 wager, address tokenAddress, uint256 multiplier) internal view {
    uint256 balance;
    if (tokenAddress == address(0)) {
      balance = address(Bankroll).balance;
    } else {
      balance = IERC20(tokenAddress).balanceOf(address(Bankroll));
    }
    uint256 maximumWagerValue = balance.mul(11000 - 10890).div(multiplier - 10000);
    require(wager <= maximumWagerValue, "Wager above limit");
  }

  /**
   * @dev Function to refund user in case of VRF request failling
   */
  function Dice_Refund() external nonReentrant {
    GameSession storage game = sessions[msg.sender];
    require(game.requestId != 0, "no awaiting vrf");
    require(game.blockNumber + 200 > block.number, "block number too low");
    uint256 wager = game.wager * game.numberOfBets;
    address tokenAddress = game.tokenAddress;

    delete (sessions[msg.sender]);
    delete (s_results[game.requestId]);

    if (tokenAddress == address(0)) {
      (bool success, ) = payable(msg.sender).call{value: wager}("");
      require(success, "refund failed");
    } else {
      IERC20(tokenAddress).safeTransfer(msg.sender, wager);
    }
    emit Dice_Refund_Event(msg.sender, wager, tokenAddress);
  }

  receive() external payable {
    emit Received(msg.sender, msg.value);
  }

  fallback() external payable {}

  function withdraw() external onlyOwner {
    uint256 balance = address(this).balance;
    VRFFees = 0;
    require(balance > 0, "No coin to withdraw");
    (bool success, ) = payable(msg.sender).call{value: balance}("");
    require(success, "coin withdrawal failed");
  }

  function getMaxWager(uint256 multiplier) external view returns (uint256) {
    uint256 maximumWagerValue = address(Bankroll).balance.mul(11000 - 10890).div(multiplier - 10000);
    return maximumWagerValue;
  }

  function getTokenBalance(address tokenAddress, address privateAddress) public view returns (uint256 balance) {
    IERC20 token = IERC20(tokenAddress);
    uint256 tokenBalance = token.balanceOf(privateAddress);
    return tokenBalance;
  }

  function withdrawTokens(address tokenAddress, uint256 amount) external onlyOwner {
    IERC20 token = IERC20(tokenAddress);
    uint256 tokenBalance = token.balanceOf(address(this));
    require(amount <= tokenBalance, "Insufficient token balance");
    token.safeTransfer(msg.sender, amount);
    uint256 newTokenBalance = token.balanceOf(address(this));
    require(tokenBalance - newTokenBalance == amount, "Token transfer failed");
  }
}

