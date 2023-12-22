// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.17;

interface ICamelot {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    address referrer,
    uint deadline
  ) external;
  function getAmountsOut(uint amountIn, address[] calldata path) external returns (uint[] memory amounts);
}
