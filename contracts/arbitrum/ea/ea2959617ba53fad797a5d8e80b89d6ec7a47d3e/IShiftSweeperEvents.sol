// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./ITroveMarketplace.sol";
import "./BuyOrder.sol";

interface IShiftSweeperEvents {
  event SuccessBuyItem(
    address indexed _nftAddress,
    uint256 _tokenId,
    // address indexed _seller,
    address indexed _buyer,
    uint256 _quantity,
    uint256 _price
  );

  event CaughtFailureBuyItem(
    address indexed _nftAddress,
    uint256 _tokenId,
    // address indexed _seller,
    address indexed _buyer,
    uint256 _quantity,
    uint256 _price,
    bytes _errorReason
  );

  event RefundedToken(address tokenAddress, uint256 amount);
}

