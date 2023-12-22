// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IKeeperRegistry {
  function addFunds(uint256 keeperId, uint96 amount) external;

  function getMinBalanceForUpkeep(uint256 keeperId)
    external
    view
    returns (uint96);

  function getKeeperInfo(address keeper)
    external
    view
    returns (address, bool, uint96);

  function getUpkeep(uint256 keeperId)
    external
    view
    returns (
      address target,
      uint32 executeGas,
      bytes memory checkData,
      uint96 balance,
      address lastKeeper,
      address admin,
      uint64 maxValidBlocknumber,
      uint96 amountSpent,
      bool paused
    );

  function registerUpkeep(
    address target,
    uint32 gasLimit,
    address admin,
    bytes calldata checkData
  ) external returns (uint256);
}

