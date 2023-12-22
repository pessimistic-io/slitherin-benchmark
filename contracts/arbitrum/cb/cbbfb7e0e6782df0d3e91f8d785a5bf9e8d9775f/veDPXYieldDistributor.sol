// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// Contracts
import { Ownable } from "./Ownable.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

// Libraries
import { SafeMath } from "./SafeMath.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { Math } from "./Math.sol";

// Interfaces
import { IERC20 } from "./IERC20.sol";
import { IveDPX } from "./IveDPX.sol";

/// @title Distributes rewards based on the claimer's veDPX balance
/// @notice Contract forked and modified from - https://etherscan.io/address/0xc6764e58b36e26b08Fd1d2AeD4538c02171fA872#code
contract veDPXYieldDistributor is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Instances
  IveDPX public veDPX;
  IERC20 public emittedToken;

  // Constant for price precision
  uint256 public constant PRICE_PRECISION = 1e6;

  // Yield and period related
  uint256 public periodFinish;
  uint256 public lastUpdateTime;
  uint256 public yieldRate;
  uint256 public yieldDuration = 604800; // 7 * 86400  (7 days)
  mapping(address => bool) public reward_notifiers;

  // Yield tracking
  uint256 public yieldPerVeDPXStored = 0;
  mapping(address => uint256) public userYieldPerTokenPaid;
  mapping(address => uint256) public yields;

  // veDPX tracking
  uint256 public totalVeDPXParticipating = 0;
  uint256 public totalVeDPXSupplyStored = 0;
  mapping(address => bool) public userIsInitialized;
  mapping(address => uint256) public userVeDPXCheckpointed;
  mapping(address => uint256) public userVeDPXEndpointCheckpointed;
  mapping(address => uint256) private lastRewardClaimTime; // staker addr -> timestamp

  // Greylists
  mapping(address => bool) public greylist;

  // Admin booleans for emergencies
  bool public yieldCollectionPaused = false; // For emergencies

  struct LockedBalance {
    int128 amount;
    uint256 end;
  }

  /* ========== MODIFIERS ========== */

  modifier notYieldCollectionPaused() {
    require(yieldCollectionPaused == false, "Yield collection is paused");
    _;
  }

  modifier checkpointUser(address account) {
    _checkpointUser(account);
    _;
  }

  /* ========== CONSTRUCTOR ========== */

  constructor(address _emittedToken, address _veDPX_address) {
    emittedToken = IERC20(_emittedToken);

    veDPX = IveDPX(_veDPX_address);
    lastUpdateTime = block.timestamp;

    reward_notifiers[msg.sender] = true;
  }

  /* ========== VIEWS ========== */

  function fractionParticipating() external view returns (uint256) {
    return
      totalVeDPXParticipating.mul(PRICE_PRECISION).div(totalVeDPXSupplyStored);
  }

  // Only positions with locked veDPX can accrue yield. Otherwise, expired-locked veDPX
  // is de-facto rewards for DPX.
  function eligibleCurrentVeDPX(address account)
    public
    view
    returns (uint256 eligible_vedpx_bal, uint256 stored_ending_timestamp)
  {
    uint256 curr_vedpx_bal = veDPX.balanceOf(account);

    // Stored is used to prevent abuse
    stored_ending_timestamp = userVeDPXEndpointCheckpointed[account];

    // Only unexpired veDPX should be eligible
    if (
      stored_ending_timestamp != 0 &&
      (block.timestamp >= stored_ending_timestamp)
    ) {
      eligible_vedpx_bal = 0;
    } else if (block.timestamp >= stored_ending_timestamp) {
      eligible_vedpx_bal = 0;
    } else {
      eligible_vedpx_bal = curr_vedpx_bal;
    }
  }

  function lastTimeYieldApplicable() public view returns (uint256) {
    return Math.min(block.timestamp, periodFinish);
  }

  function yieldPerVeDPX() public view returns (uint256) {
    if (totalVeDPXSupplyStored == 0) {
      return yieldPerVeDPXStored;
    } else {
      return (
        yieldPerVeDPXStored.add(
          lastTimeYieldApplicable()
            .sub(lastUpdateTime)
            .mul(yieldRate)
            .mul(1e18)
            .div(totalVeDPXSupplyStored)
        )
      );
    }
  }

  function earned(address account) public view returns (uint256) {
    // Uninitialized users should not earn anything yet
    if (!userIsInitialized[account]) return 0;

    // Get eligible veDPX balances
    (
      uint256 eligible_current_vedpx,
      uint256 ending_timestamp
    ) = eligibleCurrentVeDPX(account);

    // If your veDPX is unlocked
    uint256 eligible_time_fraction = PRICE_PRECISION;
    if (eligible_current_vedpx == 0) {
      // And you already claimed after expiration
      if (lastRewardClaimTime[account] >= ending_timestamp) {
        // You get NOTHING. You LOSE. Good DAY ser!
        return 0;
      }
      // You haven't claimed yet
      else {
        uint256 eligible_time = (ending_timestamp).sub(
          lastRewardClaimTime[account]
        );
        uint256 total_time = (block.timestamp).sub(
          lastRewardClaimTime[account]
        );
        eligible_time_fraction = PRICE_PRECISION.mul(eligible_time).div(
          total_time
        );
      }
    }

    // If the amount of veDPX increased, only pay off based on the old balance
    // Otherwise, take the midpoint
    uint256 vedpx_balance_to_use;
    {
      uint256 old_vedpx_balance = userVeDPXCheckpointed[account];
      if (eligible_current_vedpx > old_vedpx_balance) {
        vedpx_balance_to_use = old_vedpx_balance;
      } else {
        vedpx_balance_to_use = ((eligible_current_vedpx).add(old_vedpx_balance))
          .div(2);
      }
    }

    return (
      vedpx_balance_to_use
        .mul(yieldPerVeDPX().sub(userYieldPerTokenPaid[account]))
        .mul(eligible_time_fraction)
        .div(1e18 * PRICE_PRECISION)
        .add(yields[account])
    );
  }

  function getYieldForDuration() external view returns (uint256) {
    return (yieldRate.mul(yieldDuration));
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function _checkpointUser(address account) internal {
    // Need to retro-adjust some things if the period hasn't been renewed, then start a new one
    sync();

    // Calculate the earnings first
    _syncEarned(account);

    // Get the old and the new veDPX balances
    uint256 old_vedpx_balance = userVeDPXCheckpointed[account];
    uint256 new_vedpx_balance = veDPX.balanceOf(account);

    // Update the user's stored veDPX balance
    userVeDPXCheckpointed[account] = new_vedpx_balance;

    // Update the user's stored ending timestamp
    IveDPX.LockedBalance memory curr_locked_bal_pack = veDPX.locked(account);
    userVeDPXEndpointCheckpointed[account] = curr_locked_bal_pack.end;

    // Update the total amount participating
    if (new_vedpx_balance >= old_vedpx_balance) {
      uint256 weight_diff = new_vedpx_balance.sub(old_vedpx_balance);
      totalVeDPXParticipating = totalVeDPXParticipating.add(weight_diff);
    } else {
      uint256 weight_diff = old_vedpx_balance.sub(new_vedpx_balance);
      totalVeDPXParticipating = totalVeDPXParticipating.sub(weight_diff);
    }

    // Mark the user as initialized
    if (!userIsInitialized[account]) {
      userIsInitialized[account] = true;
      lastRewardClaimTime[account] = block.timestamp;
    }
  }

  function _syncEarned(address account) internal {
    if (account != address(0)) {
      uint256 earned0 = earned(account);
      yields[account] = earned0;
      userYieldPerTokenPaid[account] = yieldPerVeDPXStored;
    }
  }

  // Anyone can checkpoint another user
  function checkpointOtherUser(address user_addr) external {
    _checkpointUser(user_addr);
  }

  // Checkpoints the user
  function checkpoint() external {
    _checkpointUser(msg.sender);
  }

  function getYield()
    external
    nonReentrant
    notYieldCollectionPaused
    checkpointUser(msg.sender)
    returns (uint256 yield0)
  {
    require(greylist[msg.sender] == false, "Address has been greylisted");

    yield0 = yields[msg.sender];
    if (yield0 > 0) {
      yields[msg.sender] = 0;
      emittedToken.safeTransfer(msg.sender, yield0);
      emit YieldCollected(msg.sender, yield0);
    }

    lastRewardClaimTime[msg.sender] = block.timestamp;
  }

  function sync() public {
    // Update the total veDPX supply
    yieldPerVeDPXStored = yieldPerVeDPX();
    totalVeDPXSupplyStored = veDPX.totalSupply();
    lastUpdateTime = lastTimeYieldApplicable();
  }

  function notifyRewardAmount(uint256 amount) external {
    // Only whitelisted addresses can notify rewards
    require(reward_notifiers[msg.sender], "Sender not whitelisted");

    // Handle the transfer of emission tokens via `transferFrom` to reduce the number
    // of transactions required and ensure correctness of the emission amount
    emittedToken.safeTransferFrom(msg.sender, address(this), amount);

    // Update some values beforehand
    sync();

    // Update the new yieldRate
    if (block.timestamp >= periodFinish) {
      yieldRate = amount.div(yieldDuration);
    } else {
      uint256 remaining = periodFinish.sub(block.timestamp);
      uint256 leftover = remaining.mul(yieldRate);
      yieldRate = amount.add(leftover).div(yieldDuration);
    }

    // Update duration-related info
    lastUpdateTime = block.timestamp;
    periodFinish = block.timestamp.add(yieldDuration);

    emit RewardAdded(amount, yieldRate);
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  // Added to support recovering LP Yield and other mistaken tokens from other systems to be distributed to holders
  function recoverERC20(address tokenAddress, uint256 tokenAmount)
    external
    onlyOwner
  {
    // Only the owner address can ever receive the recovery withdrawal
    IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
    emit RecoveredERC20(tokenAddress, tokenAmount);
  }

  function setYieldDuration(uint256 _yieldDuration) external onlyOwner {
    require(
      periodFinish == 0 || block.timestamp > periodFinish,
      "Previous yield period must be complete before changing the duration for the new period"
    );
    yieldDuration = _yieldDuration;
    emit YieldDurationUpdated(yieldDuration);
  }

  function greylistAddress(address _address) external onlyOwner {
    greylist[_address] = !(greylist[_address]);
  }

  function toggleRewardNotifier(address notifier_addr) external onlyOwner {
    reward_notifiers[notifier_addr] = !reward_notifiers[notifier_addr];
  }

  function setPauses(bool _yieldCollectionPaused) external onlyOwner {
    yieldCollectionPaused = _yieldCollectionPaused;
  }

  function setYieldRate(uint256 _new_rate0, bool sync_too) external onlyOwner {
    yieldRate = _new_rate0;

    if (sync_too) {
      sync();
    }
  }

  /* ========== EVENTS ========== */

  event RewardAdded(uint256 reward, uint256 yieldRate);
  event YieldCollected(address indexed user, uint256 yield);
  event YieldDurationUpdated(uint256 newDuration);
  event RecoveredERC20(address token, uint256 amount);
}

