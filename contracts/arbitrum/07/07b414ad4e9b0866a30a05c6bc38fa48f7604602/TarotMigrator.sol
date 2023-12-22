// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Ownable } from "./Ownable.sol";
import { IERC20 } from "./IERC20.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

contract TarotMigrator is Ownable, ReentrancyGuard {
  IERC20 immutable public oldToken;
  IERC20 immutable public wrappedOldToken;
  IERC20 immutable public newToken;
  bool immutable oldTokenIsNative;
  uint256 public expectedBalance;
  uint256 public startTimestamp;
  uint256 public deadline;
  uint256 public amountMigrated;

  event SetExpectedBalance(address indexed from, uint256 oldExpectedBalance, uint256 newExpectedBalance);
  event SetStartTimestamp(address indexed from, uint256 oldStartTimestamp, uint256 newStartTimestamp);
  event SetDeadline(address indexed from, uint256 oldDeadline, uint256 newDeadline);
  event Migrate(address indexed from, uint256 amount, uint256 totalAmountMigrated);
  event Withdraw(address indexed from, address indexed to, uint256 oldAmount, uint256 newAmount);

  constructor(
    IERC20 _oldToken,
    IERC20 _wrappedOldToken,
    IERC20 _newToken,
    bool _oldTokenIsNative,
    uint256 _expectedBalance,
    uint256 _startTimestamp,
    uint256 _deadline
  ) Ownable() ReentrancyGuard() {
    oldToken = _oldToken;
    wrappedOldToken = _wrappedOldToken;
    newToken = _newToken;
    oldTokenIsNative = _oldTokenIsNative;
    expectedBalance = _expectedBalance;
    startTimestamp = _startTimestamp;
    deadline = _deadline;
  }

  function setExpectedBalance(uint256 _expectedBalance) onlyOwner external {
    uint256 oldExpectedBalance = expectedBalance;
    expectedBalance = _expectedBalance;
    emit SetExpectedBalance(msg.sender, oldExpectedBalance, expectedBalance);
  }

  function setStartTimestamp(uint256 _startTimestamp) onlyOwner external {
    uint256 oldStartTimestamp = startTimestamp;
    startTimestamp = _startTimestamp;
    emit SetStartTimestamp(msg.sender, oldStartTimestamp, startTimestamp);
  }

  function setDeadline(uint256 _deadline) onlyOwner external {
    uint256 oldDeadline = deadline;
    deadline = _deadline;
    emit SetDeadline(msg.sender, oldDeadline, deadline);
  }

  function checkExpectedBalance() public view returns (bool) {
    if (oldTokenIsNative) {
      return oldToken.balanceOf(address(wrappedOldToken)) >= expectedBalance;
    } else {
      return oldToken.totalSupply() == expectedBalance;
    }
  }

  function migrate(uint256 amount) nonReentrant external {
    require(checkExpectedBalance(), "TarotMigrator: INVALID_BALANCE");
    require(block.timestamp >= startTimestamp, "TarotMigrator: TOO_SOON");
    require(block.timestamp < deadline, "TarotMigrator: TOO_LATE");
    require(amount > 0 && oldToken.balanceOf(msg.sender) >= amount, "TarotMigrator: INVALID_AMOUNT");
    oldToken.transferFrom(msg.sender, address(this), amount);
    newToken.transfer(msg.sender, amount);
    amountMigrated += amount;
    emit Migrate(msg.sender, amount, amountMigrated);
  }

  function withdraw(address to, uint256 oldAmount, uint256 newAmount) onlyOwner external {
    require(to != address(0), "TarotMigrator: INVALID_TO");
    if (oldAmount > 0) {
      oldToken.transfer(to, oldAmount);
    }
    if (newAmount > 0) {
      newToken.transfer(to, newAmount);
    }
    emit Withdraw(msg.sender, to, oldAmount, newAmount);
  }
}
