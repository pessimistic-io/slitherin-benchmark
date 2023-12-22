// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./Ownable.sol";
import "./console.sol";

error Lottery__NotEnoughEthEntered();
error Lottery__TransferFailed();
error Lottery__NotOpen();
error Lottery__NotClosed();
error Lottery__NotEnoughBalance();
error Lottery__PickWinnerNotNeeded(
  uint256 currentBalance,
  uint256 numPlayers,
  uint256 lotteryState
);

/** @title A lottery contract
 * @author 0xL
 * @notice This contract implements a lottery that allows 1 winner per round
 * @dev This contract implements pseudo RNG
 */

contract Lottery is Ownable {
  // Enums
  enum LotteryState {
    IDLE,
    OPEN,
    CLOSED
  }

  // Variables
  uint256 private immutable i_entranceFee;
  uint256 private immutable i_interval;
  uint256 private s_round = 0;
  uint256 private s_lastTimeStamp;
  address payable[] private s_players;
  address payable[] private s_winners;
  LotteryState private s_lotteryState;
  mapping(uint256 => mapping(address => uint256)) private s_mapToEntries; // round[n] => address[j] => entries
  mapping(address => uint256) private s_mapToWinnerPrize; // winner address[n] => uint256 prize

  // Events
  event LotteryOpen();
  event LotteryEnter(address indexed player);
  event WinnerPicked(address indexed winner);
  event LotteryClose();
  event WithdrawFunds(address indexed owner, uint256 amount);

  constructor(uint256 entranceFee, uint256 interval) {
    i_entranceFee = entranceFee;
    i_interval = interval;
    s_lastTimeStamp = block.timestamp;
  }

  // Lottery functions

  /**
   * @notice Release lottery for new enters
   */
  function openLottery() external onlyOwner {
    s_lotteryState = LotteryState.OPEN;
    emit LotteryOpen();
  }

  /**
   * @notice Pause lottery for new enters
   */
  function closeLottery() public onlyOwner {
    s_lotteryState = LotteryState.CLOSED;
    emit LotteryClose();
  }

  /**
   * @notice Owner can withdraw remaining funds when lottery is closed
   * @dev Lottery needs to be closed before withdraw
   */
  function withdraw() public onlyOwner {
    if (s_lotteryState != LotteryState.CLOSED) {
      revert Lottery__NotClosed();
    }

    if (address(this).balance == 0) {
      revert Lottery__NotEnoughBalance();
    }

    uint256 balance = address(this).balance;
    (bool success, ) = owner().call{value: balance}("");
    if (!success) {
      revert Lottery__TransferFailed();
    }

    emit WithdrawFunds(owner(), balance);
  }

  /**
   * @notice User enters the lottery
   * @dev Don't allows less than entrace fee and lottery needs OPEN state
   */
  function enterLottery() public payable {
    if (msg.value < i_entranceFee) {
      revert Lottery__NotEnoughEthEntered();
    }

    if (s_lotteryState != LotteryState.OPEN) {
      revert Lottery__NotOpen();
    }

    s_mapToEntries[s_round][msg.sender]++;
    s_players.push(payable(msg.sender));
    emit LotteryEnter(msg.sender);
  }

  /**
   * @dev Check if contract is under conditions to pick a new Winner
   * The following should be true in order to enable:
   * 1. The lottery should be in an OPEN state
   * 2. Time interval should have passed
   * 3. The lottery should have more players than winners per round
   * 4. The lottery should have balance enough to split prize between winners
   */
  function canRequestAWinner() public view onlyOwner returns (bool canPick) {
    bool isOpen = (LotteryState.OPEN == s_lotteryState);
    bool timePassed = block.timestamp > (s_lastTimeStamp + i_interval);
    // bool hasPlayers = s_players.length > 0;
    bool hasPlayers = s_players.length > 0;
    bool hasBalance = address(this).balance > 0;
    canPick = (isOpen && timePassed && hasPlayers && hasBalance);
    return canPick;
  }

  /**
   * @dev Get a random number
   */
  function random() private view returns (uint256) {
    return uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, s_players)));
  }

  /**
   * @notice Owner is able to request a winner
   */
  function requestWinner() external onlyOwner {
    bool canRequest = canRequestAWinner();
    if (!canRequest) {
      revert Lottery__PickWinnerNotNeeded(
        address(this).balance,
        s_players.length,
        uint256(s_lotteryState)
      );
    }
    s_lotteryState = LotteryState.IDLE;
    fulfillWinner();
  }

  /**
   * @notice Pick a random winner and send prize
   * @dev Transfer 80% of the balance to the
   * winner wallet and 20% to owner wallet
   */
  function fulfillWinner() internal onlyOwner {
    uint256 prize = (address(this).balance / 5) * 4;
    uint256 index = random() % s_players.length;
    address payable recentWinner = s_players[index];
    s_winners.push(recentWinner);
    s_mapToWinnerPrize[recentWinner] = prize;

    (bool success, ) = recentWinner.call{value: prize}("");
    if (!success) {
      revert Lottery__TransferFailed();
    }
    (bool success2, ) = owner().call{value: address(this).balance}("");
    if (!success2) {
      revert Lottery__TransferFailed();
    }

    s_players = new address payable[](0);
    s_round++; // set a new round
    s_lotteryState = LotteryState.OPEN;
    s_lastTimeStamp = block.timestamp;

    emit WinnerPicked(recentWinner);
  }

  // View / Pure functions
  function getRound() public view returns (uint256) {
    return s_round;
  }

  function getEntranceFee() public view returns (uint256) {
    return i_entranceFee;
  }

  function getLatestTimeStamp() public view returns (uint256) {
    return s_lastTimeStamp;
  }

  function getInterval() public view returns (uint256) {
    return i_interval;
  }

  function getBalance() public view returns (uint256) {
    return address(this).balance;
  }

  function getLotteryState() public view returns (LotteryState) {
    return s_lotteryState;
  }

  function getPlayer(uint256 player) public view returns (address) {
    return s_players[player];
  }

  function getPlayerEntries(uint256 round, address player) public view returns (uint256) {
    return s_mapToEntries[round][player];
  }

  function getNumberOfPlayers() public view returns (uint256) {
    return s_players.length;
  }

  function getWinners() public view returns (address payable[] memory) {
    return s_winners;
  }

  function getWinnerPrize(address winner) public view returns (uint256) {
    return s_mapToWinnerPrize[winner];
  }
}

