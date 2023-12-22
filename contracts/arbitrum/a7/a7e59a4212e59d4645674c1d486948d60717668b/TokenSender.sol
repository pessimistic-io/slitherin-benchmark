// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {IAccountList, AllowedMsgSenders} from "./AllowedMsgSenders.sol";
import {PeriodicAccountLimits} from "./PeriodicAccountLimits.sol";
import {SafeAccessControlEnumerable} from "./SafeAccessControlEnumerable.sol";
import {WithdrawERC20} from "./WithdrawERC20.sol";
import {ITokenSender} from "./ITokenSender.sol";
import {IUintValue} from "./IUintValue.sol";
import {IERC20} from "./IERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract TokenSender is
  ITokenSender,
  AllowedMsgSenders,
  PeriodicAccountLimits,
  ReentrancyGuard,
  SafeAccessControlEnumerable,
  WithdrawERC20
{
  IUintValue private _priceOracle;
  uint256 private _priceLowerBound;

  IERC20 private immutable _outputToken;
  uint256 private immutable _outputTokenUnit;

  bytes32 public constant override SET_PRICE_ORACLE_ROLE =
    keccak256("setPriceOracle");
  bytes32 public constant override SET_PRICE_LOWER_BOUND_ROLE =
    keccak256("setPriceLowerBound");
  bytes32 public constant override SET_ALLOWED_MSG_SENDERS_ROLE =
    keccak256("setAllowedMsgSenders");
  bytes32 public constant override SET_ACCOUNT_LIMIT_RESET_PERIOD_ROLE =
    keccak256("setAccountLimitResetPeriod");
  bytes32 public constant override SET_ACCOUNT_LIMIT_PER_PERIOD_ROLE =
    keccak256("setAccountLimitPerPeriod");
  bytes32 public constant override WITHDRAW_ERC20_ROLE =
    keccak256("withdrawERC20");

  constructor(IERC20 outputToken, uint256 outputTokenDecimals) {
    _outputToken = outputToken;
    _outputTokenUnit = 10**outputTokenDecimals;
    _grantRole(SET_PRICE_ORACLE_ROLE, msg.sender);
    _grantRole(SET_PRICE_LOWER_BOUND_ROLE, msg.sender);
    _grantRole(SET_ALLOWED_MSG_SENDERS_ROLE, msg.sender);
    _grantRole(SET_ACCOUNT_LIMIT_RESET_PERIOD_ROLE, msg.sender);
    _grantRole(SET_ACCOUNT_LIMIT_PER_PERIOD_ROLE, msg.sender);
    _grantRole(WITHDRAW_ERC20_ROLE, msg.sender);
  }

  function send(address recipient, uint256 inputAmount)
    external
    override
    nonReentrant
    onlyAllowedMsgSenders
  {
    uint256 price = _priceOracle.get();
    if (price <= _priceLowerBound) return;
    uint256 outputAmount = (inputAmount * _outputTokenUnit) / price;
    if (outputAmount == 0) return;
    if (outputAmount > _outputToken.balanceOf(address(this))) return;
    if (exceedsAccountLimit(msg.sender, outputAmount)) return;
    _addAmount(msg.sender, outputAmount);
    _outputToken.transfer(recipient, outputAmount);
  }

  function setPriceOracle(IUintValue priceOracle)
    external
    override
    onlyRole(SET_PRICE_ORACLE_ROLE)
  {
    _priceOracle = priceOracle;
    emit PriceOracleChange(priceOracle);
  }

  function setPriceLowerBound(uint256 priceLowerBound)
    external
    override
    onlyRole(SET_PRICE_LOWER_BOUND_ROLE)
  {
    _priceLowerBound = priceLowerBound;
    emit PriceLowerBoundChange(priceLowerBound);
  }

  function setAllowedMsgSenders(IAccountList allowedMsgSenders)
    public
    override
    onlyRole(SET_ALLOWED_MSG_SENDERS_ROLE)
  {
    super.setAllowedMsgSenders(allowedMsgSenders);
  }

  function setAccountLimitResetPeriod(uint256 accountLimitResetPeriod)
    public
    override
    onlyRole(SET_ACCOUNT_LIMIT_RESET_PERIOD_ROLE)
  {
    super.setAccountLimitResetPeriod(accountLimitResetPeriod);
  }

  function setAccountLimitPerPeriod(uint256 accountLimitPerPeriod)
    public
    override
    onlyRole(SET_ACCOUNT_LIMIT_PER_PERIOD_ROLE)
  {
    super.setAccountLimitPerPeriod(accountLimitPerPeriod);
  }

  function getOutputToken() external view override returns (IERC20) {
    return _outputToken;
  }

  function getPriceOracle() external view override returns (IUintValue) {
    return _priceOracle;
  }

  function getPriceLowerBound() external view override returns (uint256) {
    return _priceLowerBound;
  }

  function withdrawERC20(
    address[] calldata erc20Tokens,
    uint256[] calldata amounts
  ) public override onlyRole(WITHDRAW_ERC20_ROLE) {
    super.withdrawERC20(erc20Tokens, amounts);
  }

  function withdrawERC20(address[] calldata erc20Tokens)
    public
    override
    onlyRole(WITHDRAW_ERC20_ROLE)
  {
    super.withdrawERC20(erc20Tokens);
  }
}

