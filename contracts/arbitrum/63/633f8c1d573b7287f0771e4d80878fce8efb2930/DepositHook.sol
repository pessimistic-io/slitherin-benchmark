// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./AllowedCollateralCaller.sol";
import "./DepositRecordCaller.sol";
import "./IDepositHook.sol";
import "./SafeAccessControlEnumerable.sol";
import "./TokenSenderCaller.sol";
import "./TreasuryCaller.sol";

contract DepositHook is
  IDepositHook,
  AllowedCollateralCaller,
  DepositRecordCaller,
  SafeAccessControlEnumerable,
  TokenSenderCaller,
  TreasuryCaller
{
  bool private _depositsAllowed;

  bytes32 public constant SET_COLLATERAL_ROLE = keccak256("setCollateral");
  bytes32 public constant SET_DEPOSIT_RECORD_ROLE =
    keccak256("setDepositRecord");
  bytes32 public constant SET_DEPOSITS_ALLOWED_ROLE =
    keccak256("setDepositsAllowed");
  bytes32 public constant SET_TREASURY_ROLE = keccak256("setTreasury");
  bytes32 public constant SET_TOKEN_SENDER_ROLE = keccak256("setTokenSender");

  function hook(
    address,
    address recipient,
    uint256 amountBeforeFee,
    uint256 amountAfterFee
  ) external override onlyCollateral {
    require(_depositsAllowed, "Deposits not allowed");
    _depositRecord.recordDeposit(recipient, amountAfterFee);
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

  function setTokenSender(ITokenSender tokenSender)
    public
    override
    onlyRole(SET_TOKEN_SENDER_ROLE)
  {
    super.setTokenSender(tokenSender);
  }

  function depositsAllowed() external view override returns (bool) {
    return _depositsAllowed;
  }
}

