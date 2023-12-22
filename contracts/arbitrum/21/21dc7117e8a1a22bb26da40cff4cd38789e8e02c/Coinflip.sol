// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import "./Base.sol";

import "./console.sol";

contract Coinflip is Base, VRFConsumerBaseV2 {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /* Chainlink VRF Variables */
  VRFCoordinatorV2Interface internal immutable i_vrfCOORDINATOR;
  bytes32 internal immutable i_gasLane;
  uint64 internal immutable i_subscriptionId;
  uint16 internal constant i_minimumRequestConfirmations = 3;
  uint32 internal immutable i_callbackGasLimit;

  // events
  event CoinFlip_Outcome_Event(
    address indexed playerAddress,
    uint256 wager,
    uint256 payout,
    address tokenAddress,
    uint8[] coinflipGameOutcomes,
    uint256[] payouts,
    uint32 numGames
  );
  event CoinFlip_Refund_Event(address indexed player, uint256 wager, address tokenAddress);
  event Received(address sender, uint256 value);
  event CoinFlip_Play_Event(
    address indexed playerAddress,
    uint256 wager,
    address tokenAddress,
    bool isHeads,
    uint32 numBets,
    int256 targetGain,
    int256 targetLoss,
    uint256 VRFfee
  );

  struct CoinFlipGameSession {
    uint256 wager;
    int256 targetGain;
    int256 targetLoss;
    uint256 requestID;
    address tokenAddress;
    uint64 blockNumber;
    uint32 numBets;
    bool isHeads;
  }

  mapping(address => CoinFlipGameSession) coinFlipGames;
  mapping(uint256 => address) coinIDs;

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

  function getCoinflipSessionResults(address player) external view returns (CoinFlipGameSession memory) {
    return coinFlipGames[player];
  }

  function CoinFlip_Play(
    uint256 wager,
    address tokenAddress,
    bool isHeads,
    uint32 numBets,
    int256 targetGain,
    int256 targetLoss
  ) external payable nonReentrant {
    require(!Bankroll.getStoppedStatus(), "Bankroll not active");
    require(Bankroll.getIsValidWager(address(this), tokenAddress), "set valid wager to begin");
    // address msgSender = _msgSender();

    if (targetGain == 0) {
      targetGain = type(int256).max;
    }
    if (targetLoss == 0) {
      targetLoss = type(int256).max;
    }

    require(coinFlipGames[msg.sender].requestID == 0, "AwaitingVRF: player has an ongoing game");

    require(numBets > 0 && numBets <= 20, "InvalidNumBets: numberOfBets must be between 1 and 20");

    _kellyWager(wager, tokenAddress);
    uint256 totalWager = wager.mul(numBets);
    uint256 fee = _transferWager(tokenAddress, totalWager, 800000, 22);

    uint256 requestID = _requestRandomWords(numBets);
    console.log("requestID", requestID);

    coinFlipGames[msg.sender] = CoinFlipGameSession(
      wager,
      targetGain,
      targetLoss,
      requestID,
      tokenAddress,
      uint64(block.number),
      numBets,
      isHeads
    );
    coinIDs[requestID] = msg.sender;

    emit CoinFlip_Play_Event(msg.sender, wager, tokenAddress, isHeads, numBets, targetGain, targetLoss, fee);
  }

  /**
   * @dev Function to refund user in case of VRF request failling
   */
  function CoinFlip_Refund() external nonReentrant {
    // address msgSender = _msgSender();
    CoinFlipGameSession storage game = coinFlipGames[msg.sender];
    require(game.requestID != 0, "no awaiting vrf");

    require(game.blockNumber + 200 > block.number, "blocknumber too low");

    uint256 wager = game.wager * game.numBets;
    address tokenAddress = game.tokenAddress;

    delete (coinIDs[game.requestID]);
    delete (coinFlipGames[msg.sender]);

    if (tokenAddress == address(0)) {
      (bool success, ) = payable(msg.sender).call{value: wager}("");
      require(success, "refund failed");
    } else {
      IERC20(tokenAddress).safeTransfer(msg.sender, wager);
    }
    emit CoinFlip_Refund_Event(msg.sender, wager, tokenAddress);
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
    address playerAddress = coinIDs[requestId];
    if (playerAddress == address(0)) revert();
    CoinFlipGameSession storage game = coinFlipGames[playerAddress];

    int256 totalValue;
    uint256 payout;
    uint32 i;
    uint8[] memory coinFlip = new uint8[](game.numBets);
    uint256[] memory payouts = new uint256[](game.numBets);

    address tokenAddress = game.tokenAddress;

    for (i = 0; i < game.numBets; i++) {
      if (totalValue >= int256(game.targetGain)) {
        break;
      }

      if (totalValue <= -int256(game.targetLoss)) {
        break;
      }

      coinFlip[i] = uint8(randomWords[i] % 2);

      if (coinFlip[i] == 1 && game.isHeads == true) {
        totalValue += int256((game.wager * 9800) / 10000);
        payout += (game.wager * 19800) / 10000;
        payouts[i] = (game.wager * 19800) / 10000;
        continue;
      }

      if (coinFlip[i] == 0 && game.isHeads == false) {
        totalValue += int256((game.wager * 9800) / 10000);
        payout += (game.wager * 19800) / 10000;
        payouts[i] = (game.wager * 19800) / 10000;
        continue;
      }

      totalValue -= int256(game.wager);
    }

    uint256 additionalPayout = (game.numBets - i) * game.wager;
    require(payout.add(additionalPayout) >= payout, "Payout overflow");
    payout += additionalPayout;

    emit CoinFlip_Outcome_Event(playerAddress, game.wager, payout, tokenAddress, coinFlip, payouts, i);

    _transferToBankroll(game.wager * game.numBets, tokenAddress);

    delete (coinIDs[requestId]);
    delete (coinFlipGames[playerAddress]);

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
    uint256 maximumWagerValue = (balance * 1122448) / 100000000;
    require(wager <= maximumWagerValue, "Wager above limit");
  }

  function adminResetGame(address userAddress) external onlyOwner {
    CoinFlipGameSession storage game = coinFlipGames[userAddress];
    require(game.requestID != 0, "No game to reset");
    delete (coinFlipGames[userAddress]);
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
    uint256 maximumWagerValue = (balance * 1122448) / 100000000;
    return maximumWagerValue;
  }

  receive() external payable {
    emit Received(msg.sender, msg.value);
  }

  fallback() external payable {}
}

