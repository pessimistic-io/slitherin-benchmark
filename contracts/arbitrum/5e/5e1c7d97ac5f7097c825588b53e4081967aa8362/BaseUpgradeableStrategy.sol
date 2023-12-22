//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./Initializable.sol";
import "./BaseUpgradeableStrategyStorage.sol";
import "./ControllableInit.sol";
import "./IController.sol";
import "./IRewardForwarder.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

contract BaseUpgradeableStrategy is Initializable, ControllableInit, BaseUpgradeableStrategyStorage {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  event ProfitsNotCollected(bool sell, bool floor);
  event ProfitLogInReward(uint256 profitAmount, uint256 feeAmount, uint256 timestamp);
  event ProfitAndBuybackLog(uint256 profitAmount, uint256 feeAmount, uint256 timestamp);

  modifier restricted() {
    require(msg.sender == vault() || msg.sender == controller()
      || msg.sender == governance(),
      "The sender has to be the controller, governance, or vault");
    _;
  }

  // This is only used in `investAllUnderlying()`
  // The user can still freely withdraw from the strategy
  modifier onlyNotPausedInvesting() {
    require(!pausedInvesting(), "Action blocked as the strategy is in emergency state");
    _;
  }

  constructor() public BaseUpgradeableStrategyStorage() {
  }

  function initialize(
    address _storage,
    address _underlying,
    address _vault,
    address _rewardPool,
    address _rewardToken,
    address _strategist
  ) public initializer {
    ControllableInit.initialize(
      _storage
    );
    _setUnderlying(_underlying);
    _setVault(_vault);
    _setRewardPool(_rewardPool);
    _setRewardToken(_rewardToken);
    _setStrategist(_strategist);
    _setSell(true);
    _setSellFloor(0);
    _setPausedInvesting(false);
  }

  /**
  * Schedules an upgrade for this vault's proxy.
  */
  function scheduleUpgrade(address impl) public onlyGovernance {
    _setNextImplementation(impl);
    _setNextImplementationTimestamp(block.timestamp.add(nextImplementationDelay()));
  }

  function _finalizeUpgrade() internal {
    _setNextImplementation(address(0));
    _setNextImplementationTimestamp(0);
  }

  function shouldUpgrade() external view returns (bool, address) {
    return (
      nextImplementationTimestamp() != 0
        && block.timestamp > nextImplementationTimestamp()
        && nextImplementation() != address(0),
      nextImplementation()
    );
  }

  // ========================= Internal & Private Functions =========================

  // ==================== Functionality ====================

  /**
    * @dev Same as `_notifyProfitAndBuybackInRewardToken` but does not perform a compounding buyback. Just takes fees
    *      instead.
    */
  function _notifyProfitInRewardToken(
      address _rewardToken,
      uint256 _rewardBalance
  ) internal {
      if (_rewardBalance > 100) {
          uint _feeDenominator = feeDenominator();
          uint256 strategistFee = _rewardBalance.mul(strategistFeeNumerator()).div(_feeDenominator);
          uint256 platformFee = _rewardBalance.mul(platformFeeNumerator()).div(_feeDenominator);
          uint256 profitSharingFee = _rewardBalance.mul(profitSharingNumerator()).div(_feeDenominator);

          address strategyFeeRecipient = strategist();
          address platformFeeRecipient = IController(controller()).governance();

          emit ProfitLogInReward(
              _rewardToken,
              _rewardBalance,
              profitSharingFee,
              block.timestamp
          );
          emit PlatformFeeLogInReward(
              platformFeeRecipient,
              _rewardToken,
              _rewardBalance,
              platformFee,
              block.timestamp
          );
          emit StrategistFeeLogInReward(
              strategyFeeRecipient,
              _rewardToken,
              _rewardBalance,
              strategistFee,
              block.timestamp
          );

          address rewardForwarder = IController(controller()).rewardForwarder();
          IERC20(_rewardToken).safeApprove(rewardForwarder, 0);
          IERC20(_rewardToken).safeApprove(rewardForwarder, _rewardBalance);

          // Distribute/send the fees
          IRewardForwarder(rewardForwarder).notifyFee(
              _rewardToken,
              profitSharingFee,
              strategistFee,
              platformFee
          );
      } else {
          emit ProfitLogInReward(_rewardToken, 0, 0, block.timestamp);
          emit PlatformFeeLogInReward(IController(controller()).governance(), _rewardToken, 0, 0, block.timestamp);
          emit StrategistFeeLogInReward(strategist(), _rewardToken, 0, 0, block.timestamp);
      }
  }
}

