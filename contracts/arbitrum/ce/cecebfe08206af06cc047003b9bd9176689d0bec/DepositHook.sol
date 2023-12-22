// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {ICollateral, AllowedCollateralCaller} from "./AllowedCollateralCaller.sol";
import {IDepositRecord, DepositRecordCaller} from "./DepositRecordCaller.sol";
import {IDepositHook} from "./IDepositHook.sol";
import {IAccountList, AccountListCaller} from "./AccountListCaller.sol";
import {SafeAccessControlEnumerable} from "./SafeAccessControlEnumerable.sol";
import {ITokenSender, TokenSenderCaller} from "./TokenSenderCaller.sol";
import {TreasuryCaller} from "./TreasuryCaller.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract DepositHook is
  IDepositHook,
  AccountListCaller,
  AllowedCollateralCaller,
  DepositRecordCaller,
  ReentrancyGuard,
  SafeAccessControlEnumerable,
  TokenSenderCaller,
  TreasuryCaller
{
  bool private _depositsAllowed;

  bytes32 public constant override SET_ACCOUNT_LIST_ROLE =
    keccak256("setAccountList");
  bytes32 public constant override SET_COLLATERAL_ROLE =
    keccak256("setCollateral");
  bytes32 public constant override SET_DEPOSIT_RECORD_ROLE =
    keccak256("setDepositRecord");
  bytes32 public constant override SET_DEPOSITS_ALLOWED_ROLE =
    keccak256("setDepositsAllowed");
  bytes32 public constant override SET_TREASURY_ROLE =
    keccak256("setTreasury");
  bytes32 public constant override SET_AMOUNT_MULTIPLIER_ROLE =
    keccak256("setAmountMultiplier");
  bytes32 public constant override SET_TOKEN_SENDER_ROLE =
    keccak256("setTokenSender");

  constructor() {
    _grantRole(SET_ACCOUNT_LIST_ROLE, msg.sender);
    _grantRole(SET_COLLATERAL_ROLE, msg.sender);
    _grantRole(SET_DEPOSIT_RECORD_ROLE, msg.sender);
    _grantRole(SET_DEPOSITS_ALLOWED_ROLE, msg.sender);
    _grantRole(SET_TREASURY_ROLE, msg.sender);
    _grantRole(SET_AMOUNT_MULTIPLIER_ROLE, msg.sender);
    _grantRole(SET_TOKEN_SENDER_ROLE, msg.sender);
  }

  function hook(
    address,
    address recipient,
    uint256 amountBeforeFee,
    uint256 amountAfterFee,
    bytes calldata
  ) external override nonReentrant onlyCollateral {
    if (!_depositsAllowed) revert DepositsNotAllowed();
    if (
      address(_accountList) != address(0) && _accountList.isIncluded(recipient)
    ) {
      _depositRecord.recordDeposit(recipient, amountBeforeFee);
      return;
    }
    _depositRecord.recordDeposit(recipient, amountAfterFee);
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

  function setDepositsAllowed(bool depositsAllowed)
    external
    override
    onlyRole(SET_DEPOSITS_ALLOWED_ROLE)
  {
    _depositsAllowed = depositsAllowed;
    emit DepositsAllowedChange(depositsAllowed);
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

  function getDepositsAllowed() external view override returns (bool) {
    return _depositsAllowed;
  }
}

