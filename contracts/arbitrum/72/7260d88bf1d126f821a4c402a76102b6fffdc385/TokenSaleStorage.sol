// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./TokenSaleInterface.sol";

abstract contract TokenSaleStorage is TokenSaleInterface {
    address public firstToken;
    address public secondToken;
    address public depositReceiver;
    address public buyTokenReceiver;

    uint256 public price;
    uint256 public minimumBuyAmount;
    uint256 public maximumBuyAmount;
    uint256 public depositAmount;

    mapping(address => bool) public controller;

    /// @dev Events
    event BuyEvent(
        address account,
        address buyTokenReceiver,
        uint256 firstTokenAmount,
        address firstTokenAddress,
        uint256 secondTokenAmount,
        address secondTokenAddress,
        uint256 timestamp
    );

    event DepositEvent(
        address account,
        uint256 depositAmount,
        address tokenAddress,
        address depositReceiver
    );
}

