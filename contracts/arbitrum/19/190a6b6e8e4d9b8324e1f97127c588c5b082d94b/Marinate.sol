// SPDX-License-Identifier: GNU GPLv3
pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

interface IwsUMAMI is IERC20 {
  function wrap( uint _amount ) external returns ( uint );
  function unwrap( uint _amount ) external returns ( uint );
}

contract Marinate is AccessControl, ReentrancyGuard {
  using SafeERC20 for IERC20;

  address public immutable UMAMI;
  address public immutable sUMAMI;
  address public immutable wsUMAMI;
  uint256 public totalStaked = 0;
  uint256 public totalMultipliedStaked = 0;
  mapping(address => uint256) public excessTokenRewards;
  mapping(address => uint256) public totalCumTokenRewardsPerStake;
  mapping(address => mapping(address => mapping(uint32 => uint256))) public paidCumTokenRewardsPerStake;
  mapping(address => mapping(uint32 => uint256)) public stakedBalance;
  mapping(address => mapping(uint32 => uint256)) public multipliedBalance;
  address[] public rewardTokens;
  mapping(address => bool) public isApprovedRewardToken;
  uint256 public SCALE = 1e40;
  mapping(address => mapping(uint32 => Marinator)) public marinatorInfo;
  mapping(address => mapping(address => mapping(uint32 => uint256))) public toBePaid;
  mapping(uint32 => MarinateLevel) public marinateLevels;

  struct Marinator {
    uint256 lastDepositTime;
    uint256 amount;
    uint256 wrappedAmount;
    uint256 multipliedAmount;
    uint32 unlockTime;
  }

  struct MarinateLevel {
    uint32 lockDurationInSeconds;
    uint256 multiplier;
  }

  event Stake(uint256 lockDuration, address addr, uint256 amount, uint256 multipliedAmount);
  event Withdraw(address addr, uint256 amount);
  event RewardCollection(address token, address addr, uint256 amount);
  event RewardAdded(address token, uint256 amount, uint256 rps);

  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

  constructor(address _UMAMI, address _sUMAMI, address _wsUMAMI) {
    UMAMI = _UMAMI;
    sUMAMI = _sUMAMI;
    wsUMAMI = _wsUMAMI;
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    rewardTokens.push(_UMAMI);
    isApprovedRewardToken[_UMAMI] = true;
  }

  function addReward(address token, uint256 amount) external nonReentrant {
    require(isApprovedRewardToken[token], "Token is not approved for rewards");
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    if (totalStaked == 0) {
      // Rewards which nobody is eligible for
      excessTokenRewards[token] += amount;
      return;
    }
    uint256 rewardPerStake = (amount * SCALE) / totalMultipliedStaked;
    require(rewardPerStake > 0, "insufficient reward per stake");
    totalCumTokenRewardsPerStake[token] += rewardPerStake;
    emit RewardAdded(token, amount, rewardPerStake);
  }

  function stake(uint32 levelId, uint256 amount) external {
    require(marinateLevels[levelId].lockDurationInSeconds > 0, "Invalid level");
    require(amount > 0, "Invalid stake amount");

    MarinateLevel memory level = marinateLevels[levelId];

    // Wrap the sUMAMI into wsUMAMI
    IERC20(sUMAMI).safeTransferFrom(msg.sender, address(this), amount);
    IERC20(sUMAMI).approve(wsUMAMI, amount);
    uint256 wrappedAmount = IwsUMAMI(wsUMAMI).wrap(amount);
    uint256 multipliedAmount = (wrappedAmount * level.multiplier) / SCALE;

    // Store the sender's info
    Marinator memory info = marinatorInfo[msg.sender][levelId];
    marinatorInfo[msg.sender][levelId] = Marinator({
      lastDepositTime: block.timestamp,
      amount: info.amount + amount,
      wrappedAmount: wrappedAmount,
      multipliedAmount: info.multipliedAmount + multipliedAmount,
      unlockTime: uint32(block.timestamp + level.lockDurationInSeconds)
    });

    if (stakedBalance[msg.sender][levelId] == 0) {
      // New user - not eligible for any previous rewards on any token
      for (uint256 i = 0; i < rewardTokens.length; i++) {
        address token = rewardTokens[i];
        paidCumTokenRewardsPerStake[token][msg.sender][levelId] = totalCumTokenRewardsPerStake[token];
      }
    }
    else {
      _collectRewards(levelId);
    }

    totalStaked += amount;
    totalMultipliedStaked += multipliedAmount;
    stakedBalance[msg.sender][levelId] += amount;
    multipliedBalance[msg.sender][levelId] += multipliedAmount;
    emit Stake(level.lockDurationInSeconds, msg.sender, amount, multipliedAmount);
  }

  function withdraw(uint32 levelId) public nonReentrant {
    require(marinatorInfo[msg.sender][levelId].lastDepositTime != 0, "Haven't staked");
    require(block.timestamp >= marinatorInfo[msg.sender][levelId].unlockTime, "Too soon");

    _collectRewards(levelId);
    _payRewards(levelId);

    Marinator memory info = marinatorInfo[msg.sender][levelId];
    uint256 unwrappedAmount = IwsUMAMI(wsUMAMI).unwrap(info.wrappedAmount);
    delete marinatorInfo[msg.sender][levelId];
    totalMultipliedStaked -= multipliedBalance[msg.sender][levelId];
    totalStaked -= stakedBalance[msg.sender][levelId];
    stakedBalance[msg.sender][levelId] = 0;
    multipliedBalance[msg.sender][levelId] = 0;

    IERC20(sUMAMI).safeTransfer(msg.sender, unwrappedAmount);

    emit Withdraw(msg.sender, unwrappedAmount);
  }

  function _payRewards(uint32 levelId) private {
    for (uint256 i = 0; i < rewardTokens.length; i++) {
      address token = rewardTokens[i];
      uint256 amount = toBePaid[token][msg.sender][levelId];
      IERC20(token).safeTransfer(msg.sender, amount);
      delete toBePaid[token][msg.sender][levelId];
    }
  }

  function _collectRewards(uint32 _levelId) private {
    for (uint256 i = 0; i < rewardTokens.length; i++) {
      _collectRewardsForToken(rewardTokens[i], _levelId);
    }
  }

  function _collectRewardsForToken(address token, uint32 _levelId) private {
    require(multipliedBalance[msg.sender][_levelId] > 0, "No stake for rewards");
    uint256 owedPerUnitStake = totalCumTokenRewardsPerStake[token] - paidCumTokenRewardsPerStake[token][msg.sender][_levelId];
    uint256 totalRewards = (multipliedBalance[msg.sender][_levelId] * owedPerUnitStake) / SCALE;
    paidCumTokenRewardsPerStake[token][msg.sender][_levelId] = totalCumTokenRewardsPerStake[token];
    toBePaid[token][msg.sender][_levelId] += totalRewards;
  }

  function getAvailableTokenRewards(address staker, address token, uint32 levelId) external view returns (uint256 totalRewards) {
    uint256 owedPerUnitStake = totalCumTokenRewardsPerStake[token] - paidCumTokenRewardsPerStake[token][staker][levelId];
    uint256 pendingRewards = (multipliedBalance[staker][levelId] * owedPerUnitStake) / SCALE;
    totalRewards = pendingRewards + toBePaid[token][staker][levelId];
  }

  function setMarinateLevel(uint32 _levelId, uint32 _lockDurationInSeconds, uint256 _multiplier) external onlyAdmin {
    require(marinateLevels[_levelId].lockDurationInSeconds == 0, "Level exists");
    require(_lockDurationInSeconds <= 52 weeks, "Too long");
    require(_multiplier < 10 * SCALE);
    require(_multiplier > SCALE / 10);
    marinateLevels[_levelId] = MarinateLevel(
      _lockDurationInSeconds,
      _multiplier
    );
  }

  function withdrawExcessRewards() external onlyAdmin {
    for (uint256 i = 0; i < rewardTokens.length; i++) {
      uint256 amount = excessTokenRewards[rewardTokens[i]];
      if (amount == 0) {
        continue;
      }
      IERC20(rewardTokens[i]).safeTransfer(msg.sender, amount);
      excessTokenRewards[rewardTokens[i]] = 0;
    }
  }

  function addApprovedRewardToken(address token) external onlyAdmin {
    require(!isApprovedRewardToken[token], "Reward token exists");
    isApprovedRewardToken[token] = true;
    rewardTokens.push(token);
  }

  function removeApprovedRewardToken(address token) external onlyAdmin {
    require(isApprovedRewardToken[token], "Reward token does not exist");
    for (uint256 i = 0; i < rewardTokens.length; i++) {
      if (rewardTokens[i] == token) {
        rewardTokens[i] = rewardTokens[rewardTokens.length - 1];
        rewardTokens.pop();
        isApprovedRewardToken[token] = false;
      }
    }
  }

  function setScale(uint256 _scale) external onlyAdmin {
    SCALE = _scale;
  }

  function recoverEth() external onlyAdmin {
    // For recovering eth mistakenly sent to the contract
    (bool success, ) = msg.sender.call{value: address(this).balance}("");
    require(success, "Withdraw failed");
  }

  modifier onlyAdmin() {
    require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
    _;
  }
}
