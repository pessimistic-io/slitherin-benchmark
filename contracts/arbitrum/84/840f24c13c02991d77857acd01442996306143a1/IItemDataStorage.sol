// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

interface IItemDataStorage {
  function obtainTokenId(
    uint16[] memory _characteristics
  ) external returns (uint256);

  function characteristics(
    uint256 _tokenId,
    uint16 _characteristicId
  ) external view returns (uint16);

  function characteristics(
    uint256 _tokenId
  ) external view returns (uint16[16] memory);
}

