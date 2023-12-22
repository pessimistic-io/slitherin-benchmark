// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.7;

import "./IPurchaseHook.sol";
import "./IERC20Metadata.sol";

//TODO natspec
interface IMiniSales {
  event Purchase(
    address indexed purchaser,
    address indexed recipient,
    uint256 amount,
    uint256 price
  );

  event PriceChange(uint256 newPrice);

  event PurchaseHookChange(IPurchaseHook newPurchaseHook);

  function purchase(
    address recipient,
    uint256 amount,
    uint256 price
  ) external;

  function setPrice(uint256 newPrice) external;

  function setPurchaseHook(IPurchaseHook newPurchaseHook) external;

  function getSaleToken() external view returns (IERC20Metadata);

  function getPaymentToken() external view returns (IERC20Metadata);

  function getPrice() external view returns (uint256);

  function getPurchaseHook() external view returns (IPurchaseHook);

  function getSaleTokenDecimals() external view returns (uint256);
}

