// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";

import "./FloatingPointConstants.sol";

import "./ManagerModifier.sol";
import "./ILiquidityStaker.sol";

contract LiquidityStaker is
  ILiquidityStaker,
  Pausable,
  ReentrancyGuard,
  ManagerModifier
{
  using SafeERC20 for ERC20;

  //=======================================
  // Token
  //=======================================
  ERC20 public lpToken;

  //=======================================
  // Uints
  //=======================================
  uint256 public VESTING_PERIOD;

  //=======================================
  // Structs
  //=======================================
  struct LpDeposit {
    uint256 timestamp;
    uint256 amount;
    uint256 next;
  }

  struct LpDepositListEntry {
    uint256 index;
    uint256 timestamp;
    uint256 depositedAmount;
    uint256 vestedAmount;
  }

  //=======================================
  // Mappings
  //=======================================
  mapping(address => mapping(uint256 => LpDeposit)) public deposits;
  mapping(address => uint256) public currentMaxIndex;
  mapping(address => uint256) public head;
  mapping(address => uint256) public tail;

  //=======================================
  // Events
  //=======================================
  event Staked(address sender, uint256 amount);
  event Unstaked(address sender, uint256 amount);

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {
    VESTING_PERIOD = 5 days;
  }

  //=======================================
  // External
  //=======================================
  function stake(uint256 _amount) external nonReentrant whenNotPaused {
    // Check if LP token is set
    require(
      address(lpToken) != address(0),
      "LiquidityStaker: Lp token not set"
    );

    // Transfer LP tokens to contract
    lpToken.safeTransferFrom(msg.sender, address(this), _amount);

    currentMaxIndex[msg.sender]++;

    deposits[msg.sender][currentMaxIndex[msg.sender]] = LpDeposit(
      block.timestamp,
      _amount,
      0
    );

    if (head[msg.sender] == 0) {
      head[msg.sender] = currentMaxIndex[msg.sender];
    } else {
      deposits[msg.sender][tail[msg.sender]].next = currentMaxIndex[msg.sender];
    }

    tail[msg.sender] = currentMaxIndex[msg.sender];

    emit Staked(msg.sender, _amount);
  }

  function unstake(
    uint256[] calldata _stakedDepositIndex,
    uint256[] calldata _amount
  ) external nonReentrant whenNotPaused {
    for (uint256 i = 0; i < _stakedDepositIndex.length; i++) {
      uint256 index = _stakedDepositIndex[i];
      if (i > 0) {
        require(
          index < _stakedDepositIndex[i-1],
          "LiquidityStaker: Deposits need to be unstaked in descending order"
        );
      }

      uint256 amount = _amount[i];

      LpDeposit storage deposit = deposits[msg.sender][index];
      // Check that deposit is greater than or equal to the amount to unstake
      require(
        deposit.amount >= amount,
        "LiquidityStaker: Exceeds staked amount"
      );

      // Subtract from deposit
      deposit.amount -= amount;

      // Transfer LP tokens to sender
      lpToken.safeTransfer(msg.sender, amount);

      // If the deposit is down to 0 - remove it from the list
      if (deposit.amount == 0) {
        uint256 previous = 0;
        uint256 current = head[msg.sender];
        uint256 maxIndex = currentMaxIndex[msg.sender];

        // If there are still deposits, find the previous one and update its 'next' pointer
        while (current != index && current != 0 && current < maxIndex) {
          previous = current;
          current = deposits[msg.sender][current].next;
        }

        // Adjusting the 'next' pointer of the previous deposit
        if (previous != 0) {
          deposits[msg.sender][previous].next = deposit.next;
        }

        // Moving the head if it was the one unstaked
        if (head[msg.sender] == index) {
          head[msg.sender] = deposit.next;
        }

        // Moving the tail if it was the one unstaked
        if (tail[msg.sender] == index) {
          tail[msg.sender] = previous;
        }

      }

      emit Unstaked(msg.sender, amount);
    }
  }

  function optimizeDeposits() external nonReentrant whenNotPaused {
    _optimizeDeposits(msg.sender);
  }

  function optimizeDeposits(address _staker) external onlyManager {
    _optimizeDeposits(_staker);
  }

  function listAllDeposits(
    address _staker
  )
    external
    view
    returns (LpDepositListEntry[] memory, StakerBalance memory balance)
  {
    uint256 current = head[_staker];
    uint256 length;
    while (current != 0) {
      length++;
      current = deposits[_staker][current].next;
    }

    LpDepositListEntry[] memory returnedDeposits = new LpDepositListEntry[](
      length
    );
    current = head[_staker];
    for (uint256 i = 0; i < length; i++) {
      returnedDeposits[i].index = current;
      returnedDeposits[i].timestamp = deposits[_staker][current].timestamp;
      returnedDeposits[i].depositedAmount = deposits[_staker][current].amount;
      uint256 depositDuration = block.timestamp - returnedDeposits[i].timestamp;
      if (depositDuration >= VESTING_PERIOD) {
        returnedDeposits[i].vestedAmount = returnedDeposits[i].depositedAmount;
      } else {
        returnedDeposits[i].vestedAmount =
          (returnedDeposits[i].depositedAmount * depositDuration) /
          VESTING_PERIOD;
      }
      current = deposits[_staker][current].next;
    }

    balance = currentStatusTotal(_staker, type(uint256).max);
    return (returnedDeposits, balance);
  }

  function currentStatusTotal(
    address _staker,
    uint256 _cap
  ) public view returns (StakerBalance memory balance) {
    balance.cap = _cap;
    uint256 current = head[_staker];
    uint256 countedAmount;
    while (current != 0) {
      LpDeposit storage deposit = deposits[_staker][current];
      current = deposit.next;
      balance.uncappedDepositedBalance += deposit.amount;
      if (balance.cappedDepositedBalance < _cap) {
        uint256 depositDuration = block.timestamp - deposit.timestamp;

        // Add the remaining amount to stay below or equal _cap
        countedAmount = (_cap - balance.cappedDepositedBalance) >=
          deposit.amount
          ? deposit.amount
          : (_cap - balance.cappedDepositedBalance);
        balance.cappedDepositedBalance += countedAmount;

        // Add to either fully or partially vested amounts
        if (depositDuration >= VESTING_PERIOD) {
          balance.fullyVestedBalance += countedAmount;
        } else {
          balance.partiallyVestedBalance +=
            (countedAmount * depositDuration) /
            VESTING_PERIOD;
        }
      }
    }

    balance.walletBalance = lpToken.balanceOf(_staker);
    balance.totalUncappedBalance =
      balance.uncappedDepositedBalance +
      balance.walletBalance;
  }

  function canOptimize(address _staker) public view returns (bool) {
    uint256 current = head[_staker];
    uint256 totalAmount = 0;
    uint256 lastFullyVested = 0;

    while (current != 0) {
      LpDeposit storage deposit = deposits[_staker][current];

      uint256 age = block.timestamp - deposit.timestamp;
      if (age < VESTING_PERIOD) {
        break;
      }

      totalAmount += deposit.amount;
      lastFullyVested = current;

      current = deposit.next;
    }

    return totalAmount > 0 && lastFullyVested != head[_staker];
  }

  //=======================================
  // Admin
  //=======================================
  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }

  function setVestingPeriod(uint256 _vestingPeriod) external onlyAdmin {
    VESTING_PERIOD = _vestingPeriod;
  }

  function setLpToken(address _lpToken) external onlyAdmin {
    require(
      address(_lpToken) != address(0),
      "LiquidityStaker: Invalid address"
    );

    lpToken = ERC20(_lpToken);
  }

  //=======================================
  // Internal
  //=======================================
  function _optimizeDeposits(address _staker) internal {
    uint256 current = head[_staker];
    uint256 totalAmount = 0;
    uint256 lastFullyAccrued;

    while (current != 0) {
      LpDeposit memory deposit = deposits[_staker][current];
      uint256 depositDuration = block.timestamp - deposit.timestamp;

      if (depositDuration >= VESTING_PERIOD) {
        totalAmount += deposit.amount;
        lastFullyAccrued = current;
      } else {
        break;
      }

      current = deposit.next;
    }

    if (totalAmount > 0) {
      deposits[_staker][lastFullyAccrued].amount = totalAmount;
      head[_staker] = lastFullyAccrued;
    }
  }
}

