// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

enum InputType {
  PAYMENT_TOKEN, // no swapping and use amountIn as amount
  SWAP_EXACT_IN_TO_OUT, // swap amountIn to amountOut. the first amountIn is the exact amount to swap and all of the amountOut are the minimum amounts to receive.
  SWAP_IN_TO_EXACT_OUT // not implemented
}

enum SwapRouterType {
  NONE, // no router
  UNISWAP_V2, // uniswap v2 compatible router
  UNISWAP_V3 // not implemented
}

// struct to hold the swap node data. multiple swaps can be chained together to arrive to a single payment token.
struct SwapInput {
  InputType inputType;
  SwapNode[] swapNodes;
  uint16 outTokenIndex; // the index of the payment token in the paymentTokens array
}

// struct to hold a single swap.
struct SwapNode {
  uint256 amountIn;
  uint256 amountOut;
  address router;
  address[] path;
  uint64 deadline;
  SwapRouterType routerType;
  bool ETHIn;
  bool ETHOut;
}

