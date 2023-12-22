// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20.sol";

contract SwapLogicV2 is Initializable, OwnableUpgradeable {
  address private constant NATIVE_CURRENCY = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  address private constant EMPTY_ADDRESS = address(0);
  uint256 public feeRate = 0;
  address public feeRecipient = EMPTY_ADDRESS;
  mapping(address => bool) public whitelist;

  struct CurrencyAmount {
    address currency;
    uint256 amount;
  }

  struct Whitelist {
    address target;
    bool allowed;
  }

  event Transfer(address currency, address receiver, uint256 amount);
  event Withdraw(address caller);
  event Swap(
    address inputCurrency, 
    address outputCurrency, 
    uint256 inputAmount, 
    uint256 outputAmount, 
    uint256 fee, 
    uint256 feeRate
  );

  function initialize(
    address _feeRecipient, 
    uint256 _feeRate, 
    Whitelist[] calldata _whitelist
  ) public initializer {
    __Ownable_init();
    setFeeRecipient(_feeRecipient);
    setFeeRate(_feeRate);
    setWhitelist(_whitelist);
  }

  /**
   * Returns the amount of `currency` owned by the contract.
   */
  function balanceOf(address currency) view public returns (uint256) {
    if (currency == NATIVE_CURRENCY) {
      return address(this).balance;
    } else {
      return IERC20(currency).balanceOf(address(this));
    }
  }

  /**
   * Transfer `amount` `currency` from the contract's account to `recipient`.
   */
  function _transfer(address currency, address recipient, uint256 amount) private {
    if (currency == NATIVE_CURRENCY) {
      payable(recipient).transfer(amount);
    } else {
      IERC20(currency).transfer(recipient, amount);
    }
    emit Transfer(currency, recipient, amount);
  }

  /**
   * Withdraw `currency` from the contract to `recipient`,
   * `recipient` is msg.sender when `recipient` does not exist
   */
  function withdraw(address currency, address recipient) external onlyOwner {
    _transfer(currency, recipient, balanceOf(currency));
    emit Withdraw(msg.sender);
  }

  /**
   * Execute swap operation
   */
  function execute(
    CurrencyAmount calldata input,
    address outputCurrency,
    address recipient,
    address to,
    bytes calldata callData
  ) external payable {
    require(whitelist[to], "Swap: address not allowed");

    if (input.currency == NATIVE_CURRENCY) {
      require(msg.value >= input.amount, "Swap: Insufficient balance");
    } else {
      IERC20(input.currency).transferFrom(msg.sender, address(this), input.amount);
      IERC20(input.currency).approve(to, input.amount);
    }

    (bool success, bytes memory ret) = to.call{value: msg.value}(callData);
    require(success, string(ret));

    // Get the output amount after execution
    uint256 amount = balanceOf(outputCurrency);
    uint256 fee = 0;

    // Deduct fee when feeRate > 0
    if (feeRate > 0 && feeRecipient != EMPTY_ADDRESS) {
      fee = amount * feeRate / 10000;
      amount = amount - fee;

      _transfer(outputCurrency, feeRecipient, fee);
    }

    // Transfer the remaining amount to the recipient
    _transfer(outputCurrency, recipient, amount);
    emit Swap(
      input.currency,
      outputCurrency, 
      input.amount, 
      amount, 
      fee, 
      feeRate
    );
  }

  /**
   * Configuration related functions
   */
  function setWhitelist(Whitelist[] calldata _whitelist) public onlyOwner {
    for (uint256 i = 0; i < _whitelist.length; i++) {
      whitelist[_whitelist[i].target] = _whitelist[i].allowed;
    }
  }

  function setFeeRate(uint256 _feeRate) public onlyOwner {
    feeRate = _feeRate;
  }

  function setFeeRecipient(address _feeRecipient) public onlyOwner {
    feeRecipient = _feeRecipient;
  }

  receive() external payable {}
}
