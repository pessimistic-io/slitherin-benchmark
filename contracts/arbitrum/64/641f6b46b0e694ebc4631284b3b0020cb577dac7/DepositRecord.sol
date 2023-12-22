// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./IDepositRecord.sol";
import "./AccountListCaller.sol";
import "./AllowedMsgSenders.sol";
import "./SafeAccessControlEnumerable.sol";

contract DepositRecord is
  IDepositRecord,
  AccountListCaller,
  AllowedMsgSenders,
  SafeAccessControlEnumerable
{
  uint256 private _globalNetDepositCap;
  uint256 private _globalNetDepositAmount;
  uint256 private _userDepositCap;
  mapping(address => uint256) private _userToDeposits;

  bytes32 public constant override SET_GLOBAL_NET_DEPOSIT_CAP_ROLE =
    keccak256("setGlobalNetDepositCap");
  bytes32 public constant override SET_USER_DEPOSIT_CAP_ROLE =
    keccak256("setUserDepositCap");
  bytes32 public constant override SET_ALLOWED_MSG_SENDERS_ROLE =
    keccak256("setAllowedMsgSenders");
  bytes32 public constant override SET_ACCOUNT_LIST_ROLE =
    keccak256("setAccountList");

  function recordDeposit(address user, uint256 amount)
    external
    override
    onlyAllowedMsgSenders
  {
    require(
      amount + _globalNetDepositAmount <= _globalNetDepositCap,
      "Global deposit cap exceeded"
    );
    if (!_accountList.isIncluded(user)) {
      require(
        amount + _userToDeposits[user] <= _userDepositCap,
        "User deposit cap exceeded"
      );
    }
    _globalNetDepositAmount += amount;
    _userToDeposits[user] += amount;
  }

  function recordWithdrawal(uint256 amount)
    external
    override
    onlyAllowedMsgSenders
  {
    if (_globalNetDepositAmount > amount) {
      _globalNetDepositAmount -= amount;
    } else {
      _globalNetDepositAmount = 0;
    }
  }

  function setGlobalNetDepositCap(uint256 globalNetDepositCap)
    external
    override
    onlyRole(SET_GLOBAL_NET_DEPOSIT_CAP_ROLE)
  {
    _globalNetDepositCap = globalNetDepositCap;
    emit GlobalNetDepositCapChange(globalNetDepositCap);
  }

  function setUserDepositCap(uint256 userDepositCap)
    external
    override
    onlyRole(SET_USER_DEPOSIT_CAP_ROLE)
  {
    _userDepositCap = userDepositCap;
    emit UserDepositCapChange(userDepositCap);
  }

  function setAllowedMsgSenders(IAccountList allowedMsgSenders)
    public
    virtual
    override
    onlyRole(SET_ALLOWED_MSG_SENDERS_ROLE)
  {
    super.setAllowedMsgSenders(allowedMsgSenders);
  }

  function setAccountList(IAccountList accountList)
    public
    virtual
    override
    onlyRole(SET_ACCOUNT_LIST_ROLE)
  {
    super.setAccountList(accountList);
  }

  function getGlobalNetDepositCap() external view override returns (uint256) {
    return _globalNetDepositCap;
  }

  function getGlobalNetDepositAmount()
    external
    view
    override
    returns (uint256)
  {
    return _globalNetDepositAmount;
  }

  function getUserDepositCap() external view override returns (uint256) {
    return _userDepositCap;
  }

  function getUserDepositAmount(address account)
    external
    view
    override
    returns (uint256)
  {
    return _userToDeposits[account];
  }
}

