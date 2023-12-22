// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./IUintValue.sol";
import "./IERC20.sol";

interface ITokenSender {
  event PriceChange(IUintValue price);

  event PriceMultiplierChange(uint256 priceMultiplier);

  event ScaledPriceLowerBoundChange(uint256 scaledPrice);

  function send(address recipient, uint256 unconvertedAmount) external;

  function setPrice(IUintValue price) external;

  function setPriceMultiplier(uint256 multiplier) external;

  function setScaledPriceLowerBound(uint256 lowerBound) external;

  function getOutputToken() external view returns (IERC20);

  function getPrice() external view returns (IUintValue);

  function getPriceMultiplier() external view returns (uint256);

  function getScaledPrice() external view returns (uint256);

  function getScaledPriceLowerBound() external view returns (uint256);

  function MULTIPLIER_DENOMINATOR() external view returns (uint256);

  function SET_PRICE_ROLE() external view returns (bytes32);

  function SET_PRICE_MULTIPLIER_ROLE() external view returns (bytes32);

  function SET_SCALED_PRICE_LOWER_BOUND_ROLE() external view returns (bytes32);

  function SET_ALLOWED_MSG_SENDERS_ROLE() external view returns (bytes32);

  function WITHDRAW_ERC20_ROLE() external view returns (bytes32);
}

