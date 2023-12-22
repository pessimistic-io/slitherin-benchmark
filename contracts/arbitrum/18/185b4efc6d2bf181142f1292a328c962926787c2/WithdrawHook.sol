// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./IWithdrawHook.sol";
import "./AllowedCollateralCaller.sol";
import "./DepositRecordCaller.sol";
import "./SafeAccessControlEnumerable.sol";
import "./TokenSenderCaller.sol";
import "./TreasuryCaller.sol";

contract WithdrawHook is
  IWithdrawHook,
  AllowedCollateralCaller,
  DepositRecordCaller,
  SafeAccessControlEnumerable,
  TokenSenderCaller,
  TreasuryCaller
{
  uint256 private _globalPeriodLength;
  uint256 private _globalWithdrawLimitPerPeriod;
  uint256 private _lastGlobalPeriodReset;
  uint256 private _globalAmountWithdrawnThisPeriod;

  uint256 public constant override PERCENT_DENOMINATOR = 1000000;
  uint256 public constant override MAX_GLOBAL_PERIOD_LENGTH = 7 days;
  uint256
    public constant
    override MIN_GLOBAL_WITHDRAW_LIMIT_PERCENT_PER_PERIOD = 30000;
  uint256 public immutable override MIN_GLOBAL_WITHDRAW_LIMIT_PER_PERIOD;

  bytes32 public constant override SET_COLLATERAL_ROLE =
    keccak256("setCollateral");
  bytes32 public constant override SET_DEPOSIT_RECORD_ROLE =
    keccak256("setDepositRecord");
  bytes32 public constant override SET_GLOBAL_PERIOD_LENGTH_ROLE =
    keccak256("setGlobalPeriodLength");
  bytes32 public constant override SET_GLOBAL_WITHDRAW_LIMIT_PER_PERIOD_ROLE =
    keccak256("setGlobalWithdrawLimitPerPeriod");
  bytes32 public constant override SET_TREASURY_ROLE =
    keccak256("setTreasury");
  bytes32 public constant override SET_TOKEN_SENDER_ROLE =
    keccak256("setTokenSender");

  constructor(uint256 baseTokenDecimals) {
    MIN_GLOBAL_WITHDRAW_LIMIT_PER_PERIOD = 10**baseTokenDecimals * 15;
  }

  /*
   * @dev While we could include the period length in the last reset
   * timestamp, not initially adding it means that a change in period will
   * be reflected immediately.
   *
   * We use `_amountBeforeFee` for updating global net deposits for a more
   * accurate value.
   */
  function hook(
    address funder,
    address recipient,
    uint256 amountBeforeFee,
    uint256 amountAfterFee
  ) external override onlyCollateral {
    if (_lastGlobalPeriodReset + _globalPeriodLength < block.timestamp) {
      _lastGlobalPeriodReset = block.timestamp;
      _globalAmountWithdrawnThisPeriod = 0;
    }
    require(
      _globalAmountWithdrawnThisPeriod + amountBeforeFee <=
        getEffectiveGlobalWithdrawLimitPerPeriod(),
      "Global withdraw limit exceeded"
    );
    _globalAmountWithdrawnThisPeriod += amountBeforeFee;
    _depositRecord.recordWithdrawal(amountBeforeFee);
    uint256 fee = amountBeforeFee - amountAfterFee;
    if (fee > 0) {
      _collateral.getBaseToken().transferFrom(
        address(_collateral),
        _treasury,
        fee
      );
      _tokenSender.send(recipient, fee);
    }
  }

  function setCollateral(ICollateral collateral)
    public
    override
    onlyRole(SET_COLLATERAL_ROLE)
  {
    super.setCollateral(collateral);
  }

  function setDepositRecord(IDepositRecord depositRecord)
    public
    override
    onlyRole(SET_DEPOSIT_RECORD_ROLE)
  {
    super.setDepositRecord(depositRecord);
  }

  function setGlobalPeriodLength(uint256 globalPeriodLength)
    external
    override
    onlyRole(SET_GLOBAL_PERIOD_LENGTH_ROLE)
  {
    require(
      globalPeriodLength <= MAX_GLOBAL_PERIOD_LENGTH,
      "Exceeds period limit"
    );
    _globalPeriodLength = globalPeriodLength;
    emit GlobalPeriodLengthChange(globalPeriodLength);
  }

  function setGlobalWithdrawLimitPerPeriod(
    uint256 globalWithdrawLimitPerPeriod
  ) external override onlyRole(SET_GLOBAL_WITHDRAW_LIMIT_PER_PERIOD_ROLE) {
    require(
      globalWithdrawLimitPerPeriod >= getMinGlobalWithdrawLimitPerPeriod(),
      "Limit too low"
    );
    _globalWithdrawLimitPerPeriod = globalWithdrawLimitPerPeriod;
    emit GlobalWithdrawLimitPerPeriodChange(globalWithdrawLimitPerPeriod);
  }

  function setTreasury(address treasury)
    public
    override
    onlyRole(SET_TREASURY_ROLE)
  {
    super.setTreasury(treasury);
  }

  function setTokenSender(ITokenSender tokenSender)
    public
    override
    onlyRole(SET_TOKEN_SENDER_ROLE)
  {
    super.setTokenSender(tokenSender);
  }

  function getGlobalPeriodLength() external view override returns (uint256) {
    return _globalPeriodLength;
  }

  function getGlobalWithdrawLimitPerPeriod()
    external
    view
    override
    returns (uint256)
  {
    return _globalWithdrawLimitPerPeriod;
  }

  function getLastGlobalPeriodReset()
    external
    view
    override
    returns (uint256)
  {
    return _lastGlobalPeriodReset;
  }

  function getGlobalAmountWithdrawnThisPeriod()
    external
    view
    override
    returns (uint256)
  {
    return _globalAmountWithdrawnThisPeriod;
  }

  function getEffectiveGlobalWithdrawLimitPerPeriod()
    public
    view
    override
    returns (uint256)
  {
    return
      max(_globalWithdrawLimitPerPeriod, getMinGlobalWithdrawLimitPerPeriod());
  }

  function getMinGlobalWithdrawLimitPerPeriod()
    internal
    view
    returns (uint256)
  {
    uint256 minWithdrawLimitPerPeriodFromPercent = (_depositRecord
      .getGlobalNetDepositAmount() *
      MIN_GLOBAL_WITHDRAW_LIMIT_PERCENT_PER_PERIOD) / PERCENT_DENOMINATOR;
    return
      max(
        MIN_GLOBAL_WITHDRAW_LIMIT_PER_PERIOD,
        minWithdrawLimitPerPeriodFromPercent
      );
  }

  function max(uint256 a, uint256 b) internal pure returns (uint256) {
    return a >= b ? a : b;
  }
}

