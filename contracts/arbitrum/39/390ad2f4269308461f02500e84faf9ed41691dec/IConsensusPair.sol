// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IConsensusERC20.sol";

interface IConsensusPair is IConsensusERC20 {
  function MINIMUM_LIQUIDITY() external pure returns (uint256);

  function initialize(address, address, string memory name, string memory symbol) external;

  function factory() external view returns (address);

  function token0() external view returns (address);

  function token1() external view returns (address);

  function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

  function price0CumulativeLast() external view returns (uint256);

  function price1CumulativeLast() external view returns (uint256);

  function kLast() external view returns (uint256);

  function mint(address to) external returns (uint256 liquidity);

  function burn(address to) external returns (uint256 amount0, uint256 amount1);

  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;

  function skim(address to) external;

  function sync() external;
}

