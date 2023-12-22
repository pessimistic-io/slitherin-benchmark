// SPDX-License-Identifier: MIT
//   _   _ __  ____  __
//  | | | |  \/  \ \/ /
//  | |_| | |\/| |\  /
//  |  _  | |  | |/  \
//  |_| |_|_|  |_/_/\_\
//

pragma solidity 0.8.18;

interface IConvertedGlpStrategy {
  function execute(address _tokenOut, uint256 _amount, uint256 _minAmountOut) external returns (uint256 _amountOut);

  function setWhiteListExecutor(address _executor, bool _active) external;
}

