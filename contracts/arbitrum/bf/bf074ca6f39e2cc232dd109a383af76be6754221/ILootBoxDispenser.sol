// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

interface ILootBoxDispenser {
  function dispense(address _address, uint256 _id, uint256 _amount) external;

  function dispenseBatch(
    address _address,
    uint256[] calldata _ids,
    uint256[] calldata _amounts
  ) external;

  event LootBoxesDispensed(address _address, uint256 _tokenId, uint256 _amount);
}

