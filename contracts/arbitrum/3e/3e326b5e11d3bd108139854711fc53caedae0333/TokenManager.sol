// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./ISTEADY.sol";
import "./IesSTEADY.sol";
import "./ITokenManager.sol";
import "./IesSTEADYUsage.sol";

/*
 * esSTEADY is Steadefi's escrowed governance token obtainable by converting STEADY to it
 * It's non-transferable, except from/to whitelisted addresses
 * It can be converted back to STEADY through a vesting process
 * This contract is made to receive esSTEADY deposits from users in order to allocate them to Usages (plugins) contracts
 */

contract TokenManager is Ownable, ReentrancyGuard, ITokenManager, Pausable {
  using Address for address;
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  ISTEADY public immutable STEADY; // STEADY token to convert to/from
  IesSTEADY public immutable esSTEADY; // esSTEADY token to convert to/from

  // Redeeming min/max settings
  uint256 public minRedeemRatio = 5e17; // 1:0.5
  uint256 public maxRedeemRatio = 1e18; // 1:1
  uint256 public minRedeemDuration = 15 days; // 1296000s
  uint256 public maxRedeemDuration = 90 days; // 7776000s

  /* ========== STRUCTS ========== */

  struct EsSTEADYBalance {
    uint256 allocatedAmount; // Amount of esSTEADY allocated to a Usage
    uint256 redeemingAmount; // Total amount of esSTEADY currently being redeemed
  }

  struct RedeemInfo {
    uint256 STEADYAmount; // STEADY amount to receive when vesting has ended
    uint256 esSTEADYAmount; // esSTEADY amount to redeem
    uint256 endTime;
  }

  /* ========== CONSTANTS ========== */

  uint256 public constant MAX_DEALLOCATION_FEE = 2e16; // 2%
  uint256 public constant MAX_FIXED_RATIO = 1e18; // 100%
  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== MAPPINGS ========== */

  mapping(address => mapping(address => uint256)) public usageApprovals; // Usage approvals to allocate esSTEADY
  mapping(address => mapping(address => uint256)) public override usageAllocations; // Active esSTEADY allocations to usages
  mapping(address => EsSTEADYBalance) public esSTEADYBalances; // User's esSTEADY balances
  mapping(address => RedeemInfo[]) public userRedeems; // User's redeeming instances
  mapping(address => uint256) public usagesDeallocationFee; // Fee paid when deallocating esSTEADY

  /* ========== EVENTS ========== */

  event ApproveUsage(address indexed userAddress, address indexed usageAddress, uint256 amount);
  event Convert(address indexed from, address to, uint256 amount);
  event UpdateRedeemSettings(uint256 minRedeemRatio, uint256 maxRedeemRatio, uint256 minRedeemDuration, uint256 maxRedeemDuration);
  event UpdateDeallocationFee(address indexed usageAddress, uint256 fee);
  event Redeem(address indexed userAddress, uint256 esSTEADYAmount, uint256 STEADYAmount, uint256 duration);
  event FinalizeRedeem(address indexed userAddress, uint256 esSTEADYAmount, uint256 STEADYAmount);
  event CancelRedeem(address indexed userAddress, uint256 esSTEADYAmount);
  event Allocate(address indexed userAddress, address indexed usageAddress, uint256 amount);
  event Deallocate(address indexed userAddress, address indexed usageAddress, uint256 amount, uint256 fee);

  /* ========== MODIFIERS ========== */

  /**
   * Check if a redeem entry exists
   * @param _userAddress address of redeemer
   * @param _redeemIndex index to check
   */
  modifier validateRedeem(address _userAddress, uint256 _redeemIndex) {
    require(_redeemIndex < userRedeems[_userAddress].length, "validateRedeem: redeem entry does not exist");
    _;
  }

  /* ========== CONSTRUCTOR ========== */

  /**
   * @param _STEADY address of STEADY token
   * @param _esSTEADY address of esSTEADY token
   */
  constructor(ISTEADY _STEADY, IesSTEADY _esSTEADY) {
    require(address(_STEADY) != address(0), "Invalid 0 address");
    require(address(_esSTEADY) != address(0), "Invalid 0 address");

    STEADY = _STEADY;
    esSTEADY = _esSTEADY;

    _pause(); // Pause redemption at the start
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
   * Returns user's esSTEADY balances
   * @param _userAddress user address
   * @return allocatedAmount amount of esSTEADY allocated to a plugin in 1e18
   * @return redeemingAmount amount of esSTEADY being redeemed in 1e18
   */
  function getEsSTEADYBalance(address _userAddress) external view returns (uint256 allocatedAmount, uint256 redeemingAmount) {
    EsSTEADYBalance storage balance = esSTEADYBalances[_userAddress];
    return (balance.allocatedAmount, balance.redeemingAmount);
  }

  /**
   * Returns redeemable STEADY for "amount" of esSTEADY vested for "duration" seconds
   * @param _amount amount of esSTEADY being redeemed in 1e18
   * @param _duration duration of redemption
   * @return amount amount of STEADY to receive after redemption is completed in 1e18
   */
  function getSTEADYByVestingDuration(uint256 _amount, uint256 _duration) public view returns (uint256) {
    if (_duration < minRedeemDuration) {
      return 0;
    }

    // capped to maxRedeemDuration
    if (_duration > maxRedeemDuration) {
      return _amount * (maxRedeemRatio) / (SAFE_MULTIPLIER);
    }

    uint256 ratio = minRedeemRatio + (
      (_duration - (minRedeemDuration)) * (maxRedeemRatio - (minRedeemRatio))
      / (maxRedeemDuration - (minRedeemDuration))
    );

    return _amount * (ratio)/ (SAFE_MULTIPLIER);
  }

  /**
   * Returns quantity of "userAddress" pending redeems
   * @param _userAddress user address
   * @return pendingRedeems amount of esSTEADY allocated to a plugin in 1e18
   */
  function getUserRedeemsLength(address _userAddress) external view returns (uint256) {
    return userRedeems[_userAddress].length;
  }

  /**
   * Returns "userAddress" info for a pending redeem identified by "redeemIndex"
   * @param _userAddress address of redeemer
   * @param _redeemIndex index to check
   * @return STEADYAmount amount of STEADY in redemption
   * @return esSTEADYAmount amount of esSTEADY redeemable in this redemption
   * @return endTime timestamp when redemption is fully complete
   */
  function getUserRedeem(address _userAddress, uint256 _redeemIndex)
    external view validateRedeem(_userAddress, _redeemIndex)
    returns (uint256 STEADYAmount, uint256 esSTEADYAmount, uint256 endTime)
  {
    RedeemInfo storage _redeem = userRedeems[_userAddress][_redeemIndex];
    return (_redeem.STEADYAmount, _redeem.esSTEADYAmount, _redeem.endTime);
  }

  /**
   * Returns approved esSTEADY to allocate from "userAddress" to "usageAddress"
   * @param _userAddress address of user
   * @param _usageAddress address of plugin
   * @return amount amount of esSTEADY approved to plugin in 1e18
   */
  function getUsageApproval(address _userAddress, address _usageAddress) external view returns (uint256) {
    return usageApprovals[_userAddress][_usageAddress];
  }

  /**
   * Returns allocated esSTEADY from "userAddress" to "usageAddress"
   * @param _userAddress address of user
   * @param _usageAddress address of plugin
   * @return amount amount of esSTEADY allocated to plugin in 1e18
   */
  function getUsageAllocation(address _userAddress, address _usageAddress) external view returns (uint256) {
    return usageAllocations[_userAddress][_usageAddress];
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
   * Convert STEADY to esSTEADY
   * @param _amount amount of STEADY to convert in 1e18
   */
  function convert(uint256 _amount) external nonReentrant {
    _convert(_amount, msg.sender);
  }

  /**
   * Convert STEADY to esSTEADY to "to" address
   * @param _amount amount of STEADY to convert in 1e18
   * @param _to address to convert to
   */
  function convertTo(uint256 _amount, address _to) external override nonReentrant {
    require(address(msg.sender).isContract(), "convertTo: not allowed");

    _convert(_amount, _to);
  }

  /**
   * Approves "usage" address to get allocations up to "amount" of esSTEADY from msg.sender
   * @param _usage address of usage plugin
   * @param _amount amount of esSTEADY to approve in 1e18
   */
  function approveUsage(IesSTEADYUsage _usage, uint256 _amount) external nonReentrant {
    require(address(_usage) != address(0), "approveUsage: approve to the zero address");

    usageApprovals[msg.sender][address(_usage)] = _amount;
    emit ApproveUsage(msg.sender, address(_usage), _amount);
  }

  /**
   * Initiates redeem process (esSTEADY to STEADY)
   * @param _esSTEADYAmount amount of esSTEADY to redeem
   * @param _duration selected timestamp of redemption completion
   */
  function redeem(uint256 _esSTEADYAmount, uint256 _duration) external nonReentrant whenNotPaused {
    require(_esSTEADYAmount > 0, "redeem: amount cannot be null");
    require(_duration >= minRedeemDuration, "redeem: duration too low");
    require(_duration <= maxRedeemDuration, "redeem: duration too high");

    IERC20(address(esSTEADY)).safeTransferFrom(msg.sender, address(this), _esSTEADYAmount);
    EsSTEADYBalance storage balance = esSTEADYBalances[msg.sender];

    // get corresponding STEADY amount
    uint256 STEADYAmount = getSTEADYByVestingDuration(_esSTEADYAmount, _duration);
    emit Redeem(msg.sender, _esSTEADYAmount, STEADYAmount, _duration);

    // if redeeming is not immediate, go through vesting process
    if (_duration > 0) {
      // add to SBT total
      balance.redeemingAmount = balance.redeemingAmount + (_esSTEADYAmount);

      // add redeeming entry
      userRedeems[msg.sender].push(RedeemInfo(STEADYAmount, _esSTEADYAmount, _currentBlockTimestamp() + (_duration)));
    } else {
      // immediately redeem for STEADY
      _finalizeRedeem(msg.sender, _esSTEADYAmount, STEADYAmount);
    }
  }

  /**
   * Finalizes redeem process when vesting duration has been reached
   * @param _redeemIndex redemption index
   * Can only be called by the redeem entry owner
   */
  function finalizeRedeem(uint256 _redeemIndex) external nonReentrant validateRedeem(msg.sender, _redeemIndex) {
    EsSTEADYBalance storage balance = esSTEADYBalances[msg.sender];
    RedeemInfo storage _redeem = userRedeems[msg.sender][_redeemIndex];
    require(_currentBlockTimestamp() >= _redeem.endTime, "finalizeRedeem: vesting duration has not ended yet");

    // remove from SBT total
    balance.redeemingAmount = balance.redeemingAmount - (_redeem.esSTEADYAmount);
    _finalizeRedeem(msg.sender, _redeem.esSTEADYAmount, _redeem.STEADYAmount);

    // remove redeem entry
    _deleteRedeemEntry(_redeemIndex);
  }

  /**
   * Cancels an ongoing redeem entry
   * @param _redeemIndex redemption index
   * Can only be called by its owner
   */
  function cancelRedeem(uint256 _redeemIndex) external nonReentrant validateRedeem(msg.sender, _redeemIndex) {
    EsSTEADYBalance storage balance = esSTEADYBalances[msg.sender];
    RedeemInfo storage _redeem = userRedeems[msg.sender][_redeemIndex];

    // make redeeming esSTEADY available again
    balance.redeemingAmount = balance.redeemingAmount - (_redeem.esSTEADYAmount);
    IERC20(address(esSTEADY)).safeTransfer(msg.sender, _redeem.esSTEADYAmount);

    emit CancelRedeem(msg.sender, _redeem.esSTEADYAmount);

    // remove redeem entry
    _deleteRedeemEntry(_redeemIndex);
  }

  /**
   * Allocates caller's "amount" of available esSTEADY to "usageAddress" contract
   * args specific to usage contract must be passed into "usageData"
   * @param _usageAddress address of plugin
   * @param _amount amount of esSTEADY in 1e18
   * @param _usageData for extra data params for specific plugins
   */
  function allocate(address _usageAddress, uint256 _amount, bytes calldata _usageData) external nonReentrant {
    _allocate(msg.sender, _usageAddress, _amount);

    // allocates esSTEADY to usageContract
    IesSTEADYUsage(_usageAddress).allocate(msg.sender, _amount, _usageData);
  }

  /**
   * Allocates "amount" of available esSTEADY from "userAddress" to caller (ie usage contract)
   * @param _userAddress address of user
   * @param _amount amount of esSTEADY in 1e18
   * Caller must have an allocation approval for the required esSTEADY from "userAddress"
   */
  function allocateFromUsage(address _userAddress, uint256 _amount) external override nonReentrant {
    _allocate(_userAddress, msg.sender, _amount);
  }

  /**
   * Deallocates caller's "amount" of available esSTEADY from "usageAddress" contract
   * args specific to usage contract must be passed into "usageData"
   * @param _usageAddress address of plugin
   * @param _amount amount of esSTEADY in 1e18
   * @param _usageData for extra data params for specific plugins
   */
  function deallocate(address _usageAddress, uint256 _amount, bytes calldata _usageData) external nonReentrant {
    _deallocate(msg.sender, _usageAddress, _amount);

    // deallocate esSTEADY into usageContract
    IesSTEADYUsage(_usageAddress).deallocate(msg.sender, _amount, _usageData);
  }

  /**
   * Deallocates "amount" of allocated esSTEADY belonging to "userAddress" from caller (ie usage contract)
   * Caller can only deallocate esSTEADY from itself
   * @param _userAddress address of user
   * @param _amount amount of esSTEADY in 1e18
   */
  function deallocateFromUsage(address _userAddress, uint256 _amount) external override nonReentrant {
    _deallocate(_userAddress, msg.sender, _amount);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
   * Convert caller's "amount" of STEADY into esSTEADY to "to"
   * @param _amount amount of STEADY in 1e18
   * @param _to address to send esSTEADY to
   */
  function _convert(uint256 _amount, address _to) internal {
    require(_amount != 0, "convert: amount cannot be null");

    IERC20(address(STEADY)).safeTransferFrom(msg.sender, address(this), _amount);

    // mint new esSTEADY
    esSTEADY.mint(_to, _amount);

    emit Convert(msg.sender, _to, _amount);

  }

  /**
   * Finalizes the redeeming process for "userAddress" by transferring him "STEADYAmount" and removing "esSTEADYAmount" from supply
   * Any vesting check should be ran before calling this
   * STEADY excess is automatically burnt
   * @param _userAddress address of user finalizing redemption
   * @param _esSTEADYAmount amount of esSTEADY to remove in 1e18
   * @param _STEADYAmount amount of STEADY to transfer in 1e18
   */
  function _finalizeRedeem(address _userAddress, uint256 _esSTEADYAmount, uint256 _STEADYAmount) internal {
    uint256 STEADYExcess = _esSTEADYAmount - (_STEADYAmount);

    // sends due STEADY tokens
    IERC20(address(STEADY)).safeTransfer(_userAddress, _STEADYAmount);

    // burns STEADY excess if any
    STEADY.burn(STEADYExcess);
    esSTEADY.burn(_esSTEADYAmount);

    emit FinalizeRedeem(_userAddress, _esSTEADYAmount, _STEADYAmount);
  }

  /**
   * Allocates "userAddress" user's "amount" of available esSTEADY to "usageAddress" contract
   * @param _userAddress address of user
   * @param _usageAddress address of plugin
   * @param _amount amount of esSTEADY in 1e18
   */
  function _allocate(address _userAddress, address _usageAddress, uint256 _amount) internal {
    require(_amount > 0, "allocate: amount cannot be null");

    EsSTEADYBalance storage balance = esSTEADYBalances[_userAddress];

    // approval checks if allocation request amount has been approved by userAddress to be allocated to this usageAddress
    uint256 approvedEsSTEADY = usageApprovals[_userAddress][_usageAddress];
    require(approvedEsSTEADY >= _amount, "allocate: non authorized amount");

    // remove allocated amount from usage's approved amount
    usageApprovals[_userAddress][_usageAddress] = approvedEsSTEADY - (_amount);

    // update usage's allocatedAmount for userAddress
    usageAllocations[_userAddress][_usageAddress] = usageAllocations[_userAddress][_usageAddress] + (_amount);

    // adjust user's esSTEADY balances
    balance.allocatedAmount = balance.allocatedAmount + (_amount);
    IERC20(address(esSTEADY)).safeTransferFrom(_userAddress, address(this), _amount);

    emit Allocate(_userAddress, _usageAddress, _amount);
  }

  /**
   * Deallocates "amount" of available esSTEADY to "usageAddress" contract
   * @param _userAddress address of user
   * @param _usageAddress address of plugin
   * @param _amount amount of esSTEADY in 1e18
   */
  function _deallocate(address _userAddress, address _usageAddress, uint256 _amount) internal {
    require(_amount > 0, "deallocate: amount cannot be null");

    // check if there is enough allocated esSTEADY to this usage to deallocate
    uint256 allocatedAmount = usageAllocations[_userAddress][_usageAddress];
    require(allocatedAmount >= _amount, "deallocate: non authorized _amount");

    // remove deallocated amount from usage's allocation
    usageAllocations[_userAddress][_usageAddress] = allocatedAmount - (_amount);

    uint256 deallocationFeeAmount = _amount * (usagesDeallocationFee[_usageAddress]) / SAFE_MULTIPLIER;

    // adjust user's esSTEADY balances
    EsSTEADYBalance storage balance = esSTEADYBalances[_userAddress];
    balance.allocatedAmount = balance.allocatedAmount - (_amount);
    IERC20(address(esSTEADY)).safeTransfer(_userAddress, _amount - (deallocationFeeAmount));
    // burn corresponding STEADY and esSTEADY
    STEADY.burn(deallocationFeeAmount);
    esSTEADY.burn(deallocationFeeAmount);

    emit Deallocate(_userAddress, _usageAddress, _amount, deallocationFeeAmount);
  }

  /**
   * Deletes redemption entry
   * @param _index index of redemption
   */
  function _deleteRedeemEntry(uint256 _index) internal {
    userRedeems[msg.sender][_index] = userRedeems[msg.sender][userRedeems[msg.sender].length - 1];
    userRedeems[msg.sender].pop();
  }

  /**
   * Utility function to get the current block timestamp
   * @return timestamp
   */
  function _currentBlockTimestamp() internal view virtual returns (uint256) {
    /* solhint-disable not-rely-on-time */
    return block.timestamp;
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  /**
   * Updates all redeem ratios and durations
   * @param _minRedeemRatio min redemption ratio in 1e18
   * @param _maxRedeemRatio max redemption ratio in 1e18
   * @param _minRedeemDuration min redemption duration in timestamp
   * @param _maxRedeemDuration max redemption duration in timestamp
   */
  function updateRedeemSettings(
    uint256 _minRedeemRatio,
    uint256 _maxRedeemRatio,
    uint256 _minRedeemDuration,
    uint256 _maxRedeemDuration
  ) external onlyOwner {
    require(_minRedeemRatio <= _maxRedeemRatio, "updateRedeemSettings: wrong ratio values");
    require(_minRedeemDuration < _maxRedeemDuration, "updateRedeemSettings: wrong duration values");
    require(_maxRedeemRatio <= MAX_FIXED_RATIO, "updateRedeemSettings: wrong ratio values"); // should never exceed 100%

    minRedeemRatio = _minRedeemRatio;
    maxRedeemRatio = _maxRedeemRatio;
    minRedeemDuration = _minRedeemDuration;
    maxRedeemDuration = _maxRedeemDuration;

    emit UpdateRedeemSettings(_minRedeemRatio, _maxRedeemRatio, _minRedeemDuration, _maxRedeemDuration);
  }

  /**
   * Updates fee paid by users when deallocating from "usageAddress"
   * @param _usageAddress address of plugin
   * @param _fee deallocation fee in 1e18
   */
  function updateDeallocationFee(address _usageAddress, uint256 _fee) external onlyOwner {
    require(_fee <= MAX_DEALLOCATION_FEE, "updateDeallocationFee: too high");

    usagesDeallocationFee[_usageAddress] = _fee;

    emit UpdateDeallocationFee(_usageAddress, _fee);
  }

  /**
   * Pause contract not allowing for redemption
   */
  function pause() external onlyOwner {
    _pause();
  }

  /**
   * Unpause contract allowing for redemption
   */
  function unpause() external onlyOwner {
    _unpause();
  }
}

