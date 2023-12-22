// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./AllowedMsgSenders.sol";
import "./SafeAccessControlEnumerable.sol";
import "./WithdrawERC20.sol";
import "./ITokenSender.sol";
import "./IUintValue.sol";
import "./IERC20.sol";

contract TokenSender is
  ITokenSender,
  AllowedMsgSenders,
  SafeAccessControlEnumerable,
  WithdrawERC20
{
  IUintValue private _price;
  uint256 private _priceMultiplier;
  uint256 private _scaledPriceLowerBound;

  IERC20 private immutable _outputToken;
  uint256 private immutable _outputTokenDecimalsFactor;

  uint256 public constant override MULTIPLIER_DENOMINATOR = 10000;
  bytes32 public constant override SET_PRICE_ROLE = keccak256("setPrice");
  bytes32 public constant override SET_PRICE_MULTIPLIER_ROLE =
    keccak256("setPriceMultiplier");
  bytes32 public constant override SET_SCALED_PRICE_LOWER_BOUND_ROLE =
    keccak256("setScaledPriceLowerBound");
  bytes32 public constant override SET_ALLOWED_MSG_SENDERS_ROLE =
    keccak256("setAllowedMsgSenders");
  bytes32 public constant override WITHDRAW_ERC20_ROLE =
    keccak256("withdrawERC20");

  constructor(IERC20 outputToken, uint256 outputTokenDecimals) {
    _outputToken = outputToken;
    _outputTokenDecimalsFactor = 10**outputTokenDecimals;
  }

  function send(address recipient, uint256 unconvertedAmount)
    external
    override
    onlyAllowedMsgSenders
  {
    uint256 scaledPrice = getScaledPrice();
    if (scaledPrice <= _scaledPriceLowerBound) return;
    uint256 outputAmount = (unconvertedAmount * _outputTokenDecimalsFactor) /
      scaledPrice;
    if (outputAmount == 0) return;
    if (outputAmount > _outputToken.balanceOf(address(this))) return;
    _outputToken.transfer(recipient, outputAmount);
  }

  function setPrice(IUintValue price)
    external
    override
    onlyRole(SET_PRICE_ROLE)
  {
    _price = price;
    emit PriceChange(price);
  }

  function setPriceMultiplier(uint256 multiplier)
    external
    override
    onlyRole(SET_PRICE_MULTIPLIER_ROLE)
  {
    _priceMultiplier = multiplier;
    emit PriceMultiplierChange(multiplier);
  }

  function setScaledPriceLowerBound(uint256 lowerBound)
    external
    override
    onlyRole(SET_SCALED_PRICE_LOWER_BOUND_ROLE)
  {
    _scaledPriceLowerBound = lowerBound;
    emit ScaledPriceLowerBoundChange(lowerBound);
  }

  function setAllowedMsgSenders(IAccountList allowedMsgSenders)
    public
    override
    onlyRole(SET_ALLOWED_MSG_SENDERS_ROLE)
  {
    super.setAllowedMsgSenders(allowedMsgSenders);
  }

  function getOutputToken() external view override returns (IERC20) {
    return _outputToken;
  }

  function getPrice() external view override returns (IUintValue) {
    return _price;
  }

  function getPriceMultiplier() external view override returns (uint256) {
    return _priceMultiplier;
  }

  function getScaledPrice() public view override returns (uint256) {
    return (_price.get() * _priceMultiplier) / MULTIPLIER_DENOMINATOR;
  }

  function getScaledPriceLowerBound()
    external
    view
    override
    returns (uint256)
  {
    return _scaledPriceLowerBound;
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

