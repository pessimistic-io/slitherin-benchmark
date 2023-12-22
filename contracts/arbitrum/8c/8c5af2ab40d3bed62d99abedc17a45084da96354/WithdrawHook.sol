// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IWithdrawHook} from "./IWithdrawHook.sol";
import {ICollateral, AllowedCollateralCaller} from "./AllowedCollateralCaller.sol";
import {IDepositRecord, DepositRecordCaller} from "./DepositRecordCaller.sol";
import {IAccountList, AccountListCaller} from "./AccountListCaller.sol";
import {SafeAccessControlEnumerable} from "./SafeAccessControlEnumerable.sol";
import {ITokenSender, TokenSenderCaller} from "./TokenSenderCaller.sol";
import {TreasuryCaller} from "./TreasuryCaller.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract WithdrawHook is
  IWithdrawHook,
  AccountListCaller,
  AllowedCollateralCaller,
  DepositRecordCaller,
  ReentrancyGuard,
  SafeAccessControlEnumerable,
  TokenSenderCaller,
  TreasuryCaller
{
  uint256 private _globalPeriodLength;
  uint256 private _globalWithdrawLimitPerPeriod;
  uint256 private _lastGlobalPeriodReset;
  uint256 private _globalAmountWithdrawnThisPeriod;

  uint256 public constant override MAX_GLOBAL_PERIOD_LENGTH = 7 days;
  uint256
    public constant
    override MIN_GLOBAL_WITHDRAW_LIMIT_PERCENT_PER_PERIOD = 30000;
  uint256 public immutable override MIN_GLOBAL_WITHDRAW_LIMIT_PER_PERIOD;

  bytes32 public constant override SET_ACCOUNT_LIST_ROLE =
    keccak256("setAccountList");
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
  bytes32 public constant override SET_AMOUNT_MULTIPLIER_ROLE =
    keccak256("setAmountMultiplier");
  bytes32 public constant override SET_TOKEN_SENDER_ROLE =
    keccak256("setTokenSender");

  constructor(uint256 baseTokenDecimals) {
    MIN_GLOBAL_WITHDRAW_LIMIT_PER_PERIOD = 10**baseTokenDecimals * 5;
    _grantRole(SET_ACCOUNT_LIST_ROLE, msg.sender);
    _grantRole(SET_COLLATERAL_ROLE, msg.sender);
    _grantRole(SET_DEPOSIT_RECORD_ROLE, msg.sender);
    _grantRole(SET_GLOBAL_PERIOD_LENGTH_ROLE, msg.sender);
    _grantRole(SET_GLOBAL_WITHDRAW_LIMIT_PER_PERIOD_ROLE, msg.sender);
    _grantRole(SET_TREASURY_ROLE, msg.sender);
    _grantRole(SET_AMOUNT_MULTIPLIER_ROLE, msg.sender);
    _grantRole(SET_TOKEN_SENDER_ROLE, msg.sender);
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
    address,
    address recipient,
    uint256 amountBeforeFee,
    uint256 amountAfterFee,
    bytes calldata
  ) external override nonReentrant onlyCollateral {
    _depositRecord.recordWithdrawal(amountBeforeFee);
    if (
      address(_accountList) != address(0) && _accountList.isIncluded(recipient)
    ) return;
    if (_lastGlobalPeriodReset + _globalPeriodLength < block.timestamp) {
      _lastGlobalPeriodReset = block.timestamp;
      _globalAmountWithdrawnThisPeriod = 0;
    }
    if (
      _globalAmountWithdrawnThisPeriod + amountBeforeFee >
      getEffectiveGlobalWithdrawLimitPerPeriod()
    ) revert GlobalWithdrawLimitExceeded();
    _globalAmountWithdrawnThisPeriod += amountBeforeFee;
    uint256 fee = amountBeforeFee - amountAfterFee;
    if (fee == 0) return;
    _collateral.getBaseToken().transferFrom(
      address(_collateral),
      _treasury,
      fee
    );
    if (address(_tokenSender) == address(0)) return;
    uint256 scaledFee = (fee * _accountToAmountMultiplier[msg.sender]) /
      PERCENT_UNIT;
    if (scaledFee == 0) return;
    _tokenSender.send(recipient, scaledFee);
  }

  function hook(
    address,
    address recipient,
    uint256 amountBeforeFee,
    uint256 amountAfterFee
  ) external override nonReentrant onlyCollateral {
    _depositRecord.recordWithdrawal(amountBeforeFee);
    if (
      address(_accountList) != address(0) && _accountList.isIncluded(recipient)
    ) return;
    if (_lastGlobalPeriodReset + _globalPeriodLength < block.timestamp) {
      _lastGlobalPeriodReset = block.timestamp;
      _globalAmountWithdrawnThisPeriod = 0;
    }
    if (
      _globalAmountWithdrawnThisPeriod + amountBeforeFee >
      getEffectiveGlobalWithdrawLimitPerPeriod()
    ) revert GlobalWithdrawLimitExceeded();
    _globalAmountWithdrawnThisPeriod += amountBeforeFee;
    uint256 fee = amountBeforeFee - amountAfterFee;
    if (fee == 0) return;
    _collateral.getBaseToken().transferFrom(
      address(_collateral),
      _treasury,
      fee
    );
    if (address(_tokenSender) == address(0)) return;
    uint256 scaledFee = (fee * _accountToAmountMultiplier[msg.sender]) /
      PERCENT_UNIT;
    if (scaledFee == 0) return;
    _tokenSender.send(recipient, scaledFee);
  }

  function setAccountList(IAccountList accountList)
    public
    virtual
    override
    onlyRole(SET_ACCOUNT_LIST_ROLE)
  {
    super.setAccountList(accountList);
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
    if (globalPeriodLength > MAX_GLOBAL_PERIOD_LENGTH)
      revert GlobalPeriodTooLong();
    _globalPeriodLength = globalPeriodLength;
    emit GlobalPeriodLengthChange(globalPeriodLength);
  }

  function setGlobalWithdrawLimitPerPeriod(
    uint256 globalWithdrawLimitPerPeriod
  ) external override onlyRole(SET_GLOBAL_WITHDRAW_LIMIT_PER_PERIOD_ROLE) {
    if (globalWithdrawLimitPerPeriod < getMinGlobalWithdrawLimitPerPeriod())
      revert GlobalWithdrawLimitTooLow();
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

  function setAmountMultiplier(address account, uint256 amountMultiplier)
    public
    override
    onlyRole(SET_AMOUNT_MULTIPLIER_ROLE)
  {
    if (account == address(0) || account != address(_collateral))
      revert InvalidAccount();
    super.setAmountMultiplier(account, amountMultiplier);
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
      MIN_GLOBAL_WITHDRAW_LIMIT_PERCENT_PER_PERIOD) / PERCENT_UNIT;
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

