// SPDX-License-Identifier: MIT LICENSE
pragma solidity 0.8.15;
import "./SafeERC20.sol";
import "./draft-ERC20Permit.sol";
import "./ERC20.sol";
import "./Ownable.sol";

contract CheeseGameMMA is Ownable {
  using SafeERC20 for ERC20;

  struct GameData {
    uint256 amountA;
    uint256 amountB;
    uint256 amountC;
  }

  mapping(address => GameData) public total;
  mapping(address => uint256) public totalSupply;
  uint256 public stopTime;
  bool public stopTimeLocked;
  uint8 public lastWinner;

  // user => token => GameData
  mapping(address => mapping(address => GameData)) public users;

  event Join(address indexed user, address indexed token, uint8 indexed index, uint256 amount);
  event StopTimeUpdate(uint256 indexed stopTime);
  event StopTimeLock(uint256 indexed stopTime);
  event Winner(uint8 indexed winner);

  constructor() {
    stopTime = block.timestamp + 7 days;
  }

  function Play(uint8 index) external payable {
    joinGame(address(0), index, msg.value);
  }

  function PlayERC20(ERC20 token, uint8 index, uint256 amount) public {
    uint256 balance = token.balanceOf(address(this));
    token.safeTransferFrom(msg.sender, address(this), amount);
    require(token.balanceOf(address(this)) == balance + amount, 'CheeseGameMMA: token transfer failed');
    joinGame(address(token), index, amount);
  }

  function PlayERC20Permit(ERC20Permit token, uint8 index, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
    token.permit(msg.sender, address(this), amount, deadline, v, r, s);
    PlayERC20(token, index, amount);
  }

  function joinGame(address token, uint8 index, uint256 amount) internal {
    require(stopTime > block.timestamp, 'CheeseGameMMA: game is over');
    require(amount > 0, 'CheeseGameMMA: amount must be greater than 0');

    if (index == 1) {
      users[msg.sender][token].amountA += amount;
      total[token].amountA += amount;
    } else if (index == 2) {
      users[msg.sender][token].amountB += amount;
      total[token].amountB += amount;
    } else if (index == 3) {
      users[msg.sender][token].amountC += amount;
      total[token].amountC += amount;
    } else {
      revert('CheeseGameMMA: index out of range');
    }

    emit Join(msg.sender, token, index, amount);
  }

  function UpdateStopTime(uint256 _stopTime) external onlyOwner {
    require(!stopTimeLocked, 'CheeseGameMMA: stop time locked');
    require(_stopTime > block.timestamp, 'CheeseGameMMA: stop time must be greater than now');
    require(_stopTime > stopTime, 'CheeseGameMMA: stop time must be greater than current stop time');
    stopTime = _stopTime;
    emit StopTimeUpdate(stopTime);
  }

  function LockStopTime() external onlyOwner {
    stopTimeLocked = true;
    emit StopTimeLock(stopTime);
  }

  function SetWinner(uint8 index) external onlyOwner {
    require(stopTime < block.timestamp, 'CheeseGameMMA: game is not over');
    require(lastWinner == 0, 'CheeseGameMMA: winner already set');
    require(index < 4, 'CheeseGameMMA: index out of range');
    require(index > 0, 'CheeseGameMMA: index out of range');

    lastWinner = index;

    emit Winner(lastWinner);
  }

  function Withdraw() external {
    uint256 amount = resolveGame(address(0));
    payable(msg.sender).transfer(amount);
  }

  function WithdrawERC20(ERC20 token) external {
    uint256 amount = resolveGame(address(token));
    token.safeTransfer(msg.sender, amount);
  }

  function resolveGame(address token) internal returns (uint256) {
    require(lastWinner > 0, 'CheeseGameMMA: winner not set');

    uint8 winner = lastWinner;
    uint256 amount;
    uint256 totalAmount;
    uint256 supply = totalSupply[token];
    if (supply == 0) {
      totalSupply[token] = token == address(0) ? address(this).balance : ERC20(token).balanceOf(address(this));
      supply = totalSupply[token];
    }

    if (winner == 1) {
      amount = users[msg.sender][token].amountA;
      users[msg.sender][token].amountA = 0;
      totalAmount = total[token].amountA;
    } else if (winner == 2) {
      amount = users[msg.sender][token].amountB;
      users[msg.sender][token].amountB = 0;
      totalAmount = total[token].amountB;
    } else if (winner == 3) {
      amount = users[msg.sender][token].amountC;
      users[msg.sender][token].amountC = 0;
      totalAmount = total[token].amountC;
    } else {
      revert('CheeseGameMMA: winner out of range');
    }

    require(amount > 0, 'CheeseGameMMA: no funds to withdraw');

    return (amount * supply) / totalAmount;
  }

  receive() external payable {}
}

