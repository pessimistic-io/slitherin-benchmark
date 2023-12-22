// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface ISwapCollector {
}

struct SwapQuote {
  address sellToken;
  address buyToken;
  uint256 sellAmount;
  bytes swapCallData;
}

