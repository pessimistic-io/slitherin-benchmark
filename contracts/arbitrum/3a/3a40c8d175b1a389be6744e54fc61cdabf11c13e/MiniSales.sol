// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.7;

import "./IMiniSales.sol";
import "./WithdrawERC20.sol";

contract MiniSales is IMiniSales, WithdrawERC20 {
  IERC20Metadata private immutable _saleToken;
  IERC20Metadata private immutable _paymentToken;
  uint256 private immutable _saleTokenDecimals;
  uint256 private _price;
  IPurchaseHook private _purchaseHook;

  constructor(
    address _newSaleToken,
    address _newPaymentToken,
    uint256 _newSaleTokenDecimals,
    address _nominatedOwner
  ) {
    _saleToken = IERC20Metadata(_newSaleToken);
    _paymentToken = IERC20Metadata(_newPaymentToken);
    // TODO add to natspec that this assumes decimals will not change
    _saleTokenDecimals = 10**_newSaleTokenDecimals;
    transferOwnership(_nominatedOwner);
  }

  function purchase(
    address _recipient,
    uint256 _saleTokenAmount,
    uint256 _purchasePrice
  ) external override nonReentrant {
    require(_purchasePrice == _price, "Price mismatch");
    if (address(_purchaseHook) != address(0)) {
      _purchaseHook.hook(_msgSender(), _recipient, _saleTokenAmount, _purchasePrice);
    }
    uint256 _paymentTokenAmount = (_saleTokenAmount * _price) / _saleTokenDecimals;
    _paymentToken.transferFrom(_msgSender(), address(this), _paymentTokenAmount);
    _saleToken.transfer(_recipient, _saleTokenAmount);
    emit Purchase(_msgSender(), _recipient, _saleTokenAmount, _price);
  }

  function setPrice(uint256 _newPrice) external override onlyOwner {
    _price = _newPrice;
    emit PriceChange(_newPrice);
  }

  function setPurchaseHook(IPurchaseHook _newPurchaseHook) external override onlyOwner {
    _purchaseHook = _newPurchaseHook;
    emit PurchaseHookChange(_newPurchaseHook);
  }

  function getSaleToken() external view override returns (IERC20Metadata) {
    return _saleToken;
  }

  function getPaymentToken() external view override returns (IERC20Metadata) {
    return _paymentToken;
  }

  function getPrice() external view override returns (uint256) {
    return _price;
  }

  function getPurchaseHook() external view override returns (IPurchaseHook) {
    return _purchaseHook;
  }

  function getSaleTokenDecimals() external view override returns (uint256) {
    return _saleTokenDecimals;
  }
}

