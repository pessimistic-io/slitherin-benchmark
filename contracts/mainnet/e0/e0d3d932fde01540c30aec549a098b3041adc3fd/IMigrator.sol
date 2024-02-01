// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

interface IMigrator {
  function execute(bytes calldata data) external;

  function whitelistTokenVault(address _tokenVault, bool _isOk) external;

  function getAmountOut(bytes calldata _data) external returns (uint256);

  function getApproximatedExecutionRewards(bytes calldata _data)
    external
    returns (uint256);
}

