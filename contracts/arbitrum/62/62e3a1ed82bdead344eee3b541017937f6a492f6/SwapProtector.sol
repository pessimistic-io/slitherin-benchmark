//  SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Ownable} from "./Ownable.sol";
import {IERC20Metadata as IERC20} from "./extensions_IERC20Metadata.sol";
import {TokenSwap} from "./TokenSwap.sol";

contract SwapProtector is Ownable {
  mapping(bytes => uint24) private pairFees;

  function getPairKey(IERC20 token0, IERC20 token1) public pure returns (bytes memory) {
    return (token0 < token1)
      ? abi.encode(token0, token1)
      : abi.encode(token1, token0);
  }

  function setPairFee(IERC20 token0, IERC20 token1, uint24 fee) public onlyOwner {
    bytes memory key = getPairKey(token0, token1);
    pairFees[key] = fee;
  }

  function getPairFee(IERC20 token0, IERC20 token1) public view returns (uint24) {
    uint24 fee = pairFees[getPairKey(token0, token1)];
    // default to 500 if it hasnt been set
    return (fee > 0) ? fee : 500;
  }

  function swap(IERC20 token0, IERC20 token1, uint amountIn, uint24 maxSlippage) internal returns (uint) {
    uint24 fee = getPairFee(token0, token1);
    return TokenSwap.swap(token0, token1, amountIn, fee, maxSlippage);
  }

  // withdraw any tokens that are sent to this contract or somehow get stuck
  function withdrawToken(IERC20 token, uint amount) external onlyOwner {
    token.transfer(msg.sender, amount);
  }
}

