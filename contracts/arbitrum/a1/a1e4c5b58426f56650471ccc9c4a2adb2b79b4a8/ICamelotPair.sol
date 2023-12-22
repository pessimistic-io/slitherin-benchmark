// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICamelotPair {
  function name() external pure returns (string memory);

  function symbol() external pure returns (string memory);

  function decimals() external pure returns (uint8);

  function getReserves() external view returns(
    uint112 reserve0,
    uint112 reserve1,
    uint16 token0FeePercent,
    uint16 token1FeePercent
  );

  function totalSupply() external view returns (uint256);

  function stableSwap() external view returns (bool);

  function token0() external view returns (address);

  function token1() external view returns (address);

  function factory() external view returns (address);

  function balanceOf(address owner) external view returns (uint256);

  function allowance(address owner, address spender) external view returns (uint256);

  function approve(address spender, uint256 value) external returns (bool);

  function transfer(address to, uint256 value) external returns (bool);

  function transferFrom(
      address from,
      address to,
      uint256 value
  ) external returns (bool);

  function kLast() external view returns (uint256);

  function precisionMultiplier0() external view returns (uint256);
  function precisionMultiplier1() external view returns (uint256);

  function FEE_DENOMINATOR() external view returns (uint256);
}

