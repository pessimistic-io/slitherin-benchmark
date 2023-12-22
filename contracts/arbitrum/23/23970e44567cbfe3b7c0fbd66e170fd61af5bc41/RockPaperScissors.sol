// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import "./Base.sol";
import "./console.sol";

contract RockPaperScissors is Base, VRFConsumerBaseV2 {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /* Chainlink VRF Variables */
  VRFCoordinatorV2Interface internal immutable i_vrfCOORDINATOR;
  bytes32 internal immutable i_gasLane;
  uint64 internal immutable i_subscriptionId;
  uint16 internal constant i_minimumRequestConfirmations = 3;
  uint32 internal immutable i_callbackGasLimit;

  event RockPaperScissors_Play_Event(
    address indexed playerAddress,
    uint256 wager,
    address tokenAddress,
    uint8 action,
    uint32 numBets,
    int256 targetGain,
    int256 targetLoss,
    uint256 VRFfee
  );

  event RockPaperScissors_Refund_Event(address indexed player, uint256 wager, address tokenAddress);
  event Received(address sender, uint256 value);
  event RockPaperScissors_Outcome_Event(
    address indexed playerAddress,
    uint256 wager,
    uint256 payout,
    address tokenAddress,
    uint8[] rockPaperScissorsGameOutcomes,
    uint8[] randomActions,
    uint256[] payouts,
    uint32 numGames
  );

  struct RockPaperScissorsGameSession {
    uint256 wager;
    int256 targetGain;
    int256 targetLoss;
    uint256 requestID;
    address tokenAddress;
    uint64 blockNumber;
    uint32 numBets;
    uint8 action;
  }

  mapping(address => RockPaperScissorsGameSession) rockPaperScissorsGames;
  mapping(uint256 => address) rockPaperScissorsIDs;

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

  function getRockPaperScissorsSession(address player) external view returns (RockPaperScissorsGameSession memory) {
    return (rockPaperScissorsGames[player]);
  }

  function RockPaperScissors_Play(
    uint256 wager,
    address tokenAddress,
    uint8 action,
    uint32 numBets,
    int256 targetGain,
    int256 targetLoss
  ) external payable nonReentrant {
    require(!Bankroll.getStoppedStatus(), "Bankroll not active");
    require(Bankroll.getIsValidWager(address(this), tokenAddress), "set valid wager to begin");

    require(action < 3, "InvalidAction");

    if (targetGain == 0) {
      targetGain = type(int256).max;
    }
    if (targetLoss == 0) {
      targetLoss = type(int256).max;
    }
    require(rockPaperScissorsGames[msg.sender].requestID == 0, "AwaitingVRF: player has an ongoing game");
    require(numBets > 0 && numBets <= 20, "InvalidNumBets: numberOfBets must be between 1 and 20");

    _kellyWager(wager, tokenAddress);
    uint256 totalWager = wager.mul(numBets);
    uint256 fee = _transferWager(tokenAddress, totalWager, 800000, 22);

    uint256 requestID = _requestRandomWords(numBets);

    rockPaperScissorsGames[msg.sender] = RockPaperScissorsGameSession(
      wager,
      targetGain,
      targetLoss,
      requestID,
      tokenAddress,
      uint64(block.number),
      numBets,
      action
    );
    rockPaperScissorsIDs[requestID] = msg.sender;

    emit RockPaperScissors_Play_Event(msg.sender, wager, tokenAddress, action, numBets, targetGain, targetLoss, fee);
  }

  function RockPaperScissors_Refund() external nonReentrant {
    address msgSender = _msgSender();
    RockPaperScissorsGameSession storage game = rockPaperScissorsGames[msgSender];
    require(game.requestID != 0, "no awaiting vrf");

    require(game.blockNumber + 200 > block.number, "blocknumber too low");

    uint256 wager = game.wager * game.numBets;
    address tokenAddress = game.tokenAddress;

    delete (rockPaperScissorsIDs[game.requestID]);
    delete (rockPaperScissorsGames[msgSender]);

    if (tokenAddress == address(0)) {
      (bool success, ) = payable(msgSender).call{value: wager}("");
      require(success, "refund failed");
    } else {
      IERC20(tokenAddress).safeTransfer(msgSender, wager);
    }
    emit RockPaperScissors_Refund_Event(msgSender, wager, tokenAddress);
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
    address playerAddress = rockPaperScissorsIDs[requestId];
    if (playerAddress == address(0)) revert();

    RockPaperScissorsGameSession storage game = rockPaperScissorsGames[playerAddress];

    uint8[] memory randomActions = new uint8[](game.numBets);
    uint8[] memory outcomes = new uint8[](game.numBets);
    uint256[] memory payouts = new uint256[](game.numBets);
    int256 totalValue;
    uint256 payout;
    uint32 i;

    address tokenAddress = game.tokenAddress;

    for (i = 0; i < game.numBets; i++) {
      if (totalValue >= int256(game.targetGain)) {
        break;
      }
      if (totalValue <= -int256(game.targetLoss)) {
        break;
      }

      randomActions[i] = uint8(randomWords[i] % 3);
      outcomes[i] = _determineRPSResult(game.action, randomActions[i]);

      if (outcomes[i] == 2) {
        payout += (game.wager * 99) / 100;
        totalValue -= int256((game.wager) / 100);
        payouts[i] = (game.wager * 99) / 100;
        continue;
      }

      if (outcomes[i] == 1) {
        payout += (game.wager * 198) / 100;
        totalValue += int256((game.wager * 98) / 100);
        payouts[i] = (game.wager * 198) / 100;
        continue;
      }

      totalValue -= int256(game.wager);
    }

    uint256 additionalPayout = (game.numBets - i) * game.wager;
    require(payout.add(additionalPayout) >= payout, "Payout overflow");
    payout += additionalPayout;

    emit RockPaperScissors_Outcome_Event(
      playerAddress,
      game.wager,
      payout,
      tokenAddress,
      outcomes,
      randomActions,
      payouts,
      i
    );

    _transferToBankroll(game.wager * game.numBets, tokenAddress);
    delete (rockPaperScissorsIDs[requestId]);
    delete (rockPaperScissorsGames[playerAddress]);
    if (payout != 0) {
      _transferPayout(playerAddress, payout, tokenAddress);
    }
  }

  function _kellyWager(uint256 wager, address tokenAddress) internal view {
    uint256 balance;
    if (tokenAddress == address(0)) {
      balance = address(Bankroll).balance;
    } else {
      balance = IERC20(tokenAddress).balanceOf(address(Bankroll));
    }
    uint256 maxWager = (balance * 1683629) / 100000000;
    require(wager <= maxWager, "Wager above limit");
  }

  // 0 loss, 1-> win, 2-> draw //0->Rock, 1-> Paper, 2->Scissors
  /**
   * @notice Determines the result of a Rock-Paper-Scissors game.
   * @param playerPick An integer representing the player's choice (0 for Rock, 1 for Paper, 2 for Scissors).
   * @param rngPick An integer representing the computer/random number generator's choice (similarly, 0 for Rock, 1 for Paper, 2 for Scissors).
   * @return A value indicating the game result from the player's perspective: 0 for a loss, 1 for a win, and 2 for a draw.
   */

  function _determineRPSResult(uint8 playerPick, uint8 rngPick) internal pure returns (uint8) {
    require(playerPick < 3 && rngPick < 3, "Invalid RPS choice");

    // Result table where the first dimension is playerPick and the second dimension is rngPick
    // Values are: 0 -> loss, 1 -> win, 2 -> draw
    uint8[3][3] memory results = [
      [2, 0, 1], // Player picks Rock
      [1, 2, 0], // Player picks Paper
      [0, 1, 2] // Player picks Scissors
    ];

    return results[playerPick][rngPick];
  }

  function adminResetGame(address userAddress) external onlyOwner {
    RockPaperScissorsGameSession storage game = rockPaperScissorsGames[userAddress];
    require(game.requestID != 0, "No game to reset");
    delete (rockPaperScissorsGames[userAddress]);
  }

  function withdraw(uint256 amount, address tokenAddress) external onlyOwner {
    if (tokenAddress == address(0)) {
      require(amount <= address(this).balance, "Insufficient Ether balance");
      (bool success, ) = payable(msg.sender).call{value: amount}("");
      require(success, "Ether transfer failed");
    } else {
      IERC20 token = IERC20(tokenAddress);
      uint256 tokenBalance = token.balanceOf(address(this));
      require(amount <= tokenBalance, "Insufficient token balance");
      token.safeTransfer(msg.sender, amount);
      uint256 newTokenBalance = token.balanceOf(address(this));
      require(tokenBalance - newTokenBalance == amount, "Token transfer failed");
    }
    // emit Withdrawn(msg.sender, tokenAddress, amount);
  }

  function getMaxWager(address tokenAddress) external view returns (uint256) {
    uint256 balance;
    if (tokenAddress == address(0)) {
      balance = address(Bankroll).balance;
    } else {
      balance = IERC20(tokenAddress).balanceOf(address(Bankroll));
    }
    uint256 maxWager = (balance * 1683629) / 100000000;
    return maxWager;
  }

  receive() external payable {
    emit Received(msg.sender, msg.value);
  }

  fallback() external payable {}
}

