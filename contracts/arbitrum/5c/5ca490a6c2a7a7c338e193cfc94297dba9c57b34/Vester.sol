// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.
//   _   _ __  ____  __
//  | | | |  \/  \ \/ /
//  | |_| | |\/| |\  /
//  |  _  | |  | |/  \
//  |_| |_|_|  |_/_/\_\
//

pragma solidity 0.8.18;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IVester } from "./IVester.sol";
import { IStaking } from "./IStaking.sol";

contract Vester is OwnableUpgradeable, ReentrancyGuardUpgradeable, IVester {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  uint256 private constant YEAR = 365 days;

  /**
   * Events
   */
  event LogVest(
    address indexed owner,
    uint256 indexed itemIndex,
    uint256 amount,
    uint256 startTime,
    uint256 endTime,
    uint256 penaltyAmount
  );
  event LogClaim(
    address indexed owner,
    uint256 indexed itemIndex,
    uint256 vestedAmount,
    uint256 unusedAmount
  );
  event LogAbort(address indexed owner, uint256 indexed itemIndex, uint256 returnAmount);
  event LogSetVestedEsHmxDestination(address indexed oldAddress, address indexed newAddress);
  event LogSetUnusedEsHmxDestination(address indexed oldAddress, address indexed newAddress);
  event LogSetHMXStaking(address indexed oldAddress, address indexed newAddress);

  /**
   * States
   */
  IERC20Upgradeable public esHMX;
  IERC20Upgradeable public hmx;

  address public vestedEsHmxDestination;
  address public unusedEsHmxDestination;

  mapping(address => mapping(uint256 => Item)) public items; // Mapping of user address => array of Vesting position
  mapping(address => uint256) public itemLastIndex; // The mapping of last Vesting position index of each user address

  IStaking public hmxStaking;

  function initialize(
    address esHMXAddress,
    address hmxAddress,
    address vestedEsHmxDestinationAddress,
    address unusedEsHmxDestinationAddress
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    esHMX = IERC20Upgradeable(esHMXAddress);
    hmx = IERC20Upgradeable(hmxAddress);
    vestedEsHmxDestination = vestedEsHmxDestinationAddress;
    unusedEsHmxDestination = unusedEsHmxDestinationAddress;

    // Santy checks
    esHMX.totalSupply();
    hmx.totalSupply();
  }

  function setVestedEsHmxDestinationAddress(
    address newVestedEsHmxDestinationAddress
  ) external onlyOwner {
    emit LogSetVestedEsHmxDestination(vestedEsHmxDestination, newVestedEsHmxDestinationAddress);
    vestedEsHmxDestination = newVestedEsHmxDestinationAddress;
  }

  function setUnusedEsHmxDestinationAddress(
    address newUnusedEsHmxDestinationAddress
  ) external onlyOwner {
    emit LogSetUnusedEsHmxDestination(unusedEsHmxDestination, newUnusedEsHmxDestinationAddress);
    unusedEsHmxDestination = newUnusedEsHmxDestinationAddress;
  }

  function setHMXStaking(address _hmxStaking) external onlyOwner {
    emit LogSetHMXStaking(address(hmxStaking), _hmxStaking);
    hmxStaking = IStaking(_hmxStaking);

    // Sanity Check
    hmxStaking.isRewarder(address(this));

    // Interaction
    esHMX.safeApprove(_hmxStaking, type(uint256).max);
  }

  function vestFor(address account, uint256 amount, uint256 duration) external nonReentrant {
    if (account == address(0) || account == address(this)) revert IVester_InvalidAddress();
    if (amount == 0) revert IVester_BadArgument();
    if (duration > YEAR) revert IVester_ExceedMaxDuration();

    uint256 totalUnlockedAmount = getUnlockAmount(amount, duration);

    Item memory item = Item({
      owner: account,
      amount: amount,
      startTime: block.timestamp,
      endTime: block.timestamp + duration,
      hasAborted: false,
      hasClaimed: false,
      lastClaimTime: block.timestamp,
      totalUnlockedAmount: totalUnlockedAmount
    });

    uint256 orderIndex = itemLastIndex[account];
    items[account][orderIndex] = item;
    itemLastIndex[account]++;

    uint256 penaltyAmount;

    unchecked {
      penaltyAmount = amount - totalUnlockedAmount;
    }

    esHMX.safeTransferFrom(msg.sender, address(this), amount);

    if (penaltyAmount > 0) {
      esHMX.safeTransfer(unusedEsHmxDestination, penaltyAmount);
    }

    emit LogVest(item.owner, orderIndex, amount, item.startTime, item.endTime, penaltyAmount);
  }

  function claim(uint256 itemIndex) external nonReentrant {
    _claim(itemIndex);
  }

  function claim(uint256[] memory itemIndexes) external nonReentrant {
    for (uint256 i = 0; i < itemIndexes.length; ) {
      _claim(itemIndexes[i]);

      unchecked {
        ++i;
      }
    }
  }

  function _claim(uint256 itemIndex) internal {
    Item memory item = items[msg.sender][itemIndex];

    if (item.amount == 0) revert IVester_PositionNotFound();
    if (item.hasClaimed) revert IVester_Claimed();
    if (item.hasAborted) revert IVester_Aborted();

    uint256 elapsedDuration = block.timestamp < item.endTime
      ? block.timestamp - item.lastClaimTime
      : item.endTime - item.lastClaimTime;
    uint256 claimable = getUnlockAmount(item.amount, elapsedDuration);

    // If vest has ended, then mark this as claimed.
    items[msg.sender][itemIndex].hasClaimed = block.timestamp >= item.endTime;

    items[msg.sender][itemIndex].lastClaimTime = block.timestamp;

    hmx.safeTransfer(item.owner, claimable);

    esHMX.safeTransfer(vestedEsHmxDestination, claimable);

    emit LogClaim(item.owner, itemIndex, claimable, item.amount - claimable);
  }

  function abort(uint256 itemIndex) external nonReentrant {
    Item memory item = items[msg.sender][itemIndex];
    if (msg.sender != item.owner) revert IVester_Unauthorized();
    if (block.timestamp > item.endTime) revert IVester_HasCompleted();
    if (item.hasClaimed) revert IVester_Claimed();
    if (item.hasAborted) revert IVester_Aborted();

    _claim(itemIndex);

    uint256 elapsedDurationSinceStart = block.timestamp - item.startTime;
    uint256 amountUsed = getUnlockAmount(item.amount, elapsedDurationSinceStart);
    uint256 returnAmount = item.totalUnlockedAmount - amountUsed;

    items[msg.sender][itemIndex].hasAborted = true;

    _stakingEsHmxForUser(msg.sender, returnAmount);

    emit LogAbort(msg.sender, itemIndex, returnAmount);
  }

  function _stakingEsHmxForUser(address user, uint256 esHmxAmount) internal {
    if (address(hmxStaking) == address(0)) revert IVester_HMXStakingNotSet();
    hmxStaking.deposit(user, address(esHMX), esHmxAmount);
  }

  function getUnlockAmount(uint256 amount, uint256 duration) public pure returns (uint256) {
    // The total unlock amount if the user wait until the end of the vest duration
    // totalUnlockAmount = (amount * vestDuration) / YEAR
    // Return the adjusted unlock amount based on the elapsed duration
    // pendingUnlockAmount = (totalUnlockAmount * elapsedDuration) / vestDuration
    // OR
    // pendingUnlockAmount = ((amount * vestDuration) / YEAR * elapsedDuration) / vestDuration
    //                     = (amount * vestDuration * elapsedDuration) / YEAR / vestDuration
    //                     = (amount * elapsedDuration) / YEAR
    return (amount * duration) / YEAR;
  }

  function getVestingPosition(
    address user,
    uint256 _limit,
    uint256 _offset
  ) external view returns (Item[] memory itemList) {
    uint256 _len = itemLastIndex[user];
    uint256 _startIndex = _offset;
    uint256 _endIndex = _offset + _limit;
    if (_startIndex > _len) return itemList;
    if (_endIndex > _len) {
      _endIndex = _len;
    }

    itemList = new Item[](_endIndex - _startIndex);

    for (uint256 i = _startIndex; i < _endIndex; ) {
      Item memory _item = items[user][i];

      itemList[i - _offset] = _item;
      unchecked {
        ++i;
      }
    }

    return itemList;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}

