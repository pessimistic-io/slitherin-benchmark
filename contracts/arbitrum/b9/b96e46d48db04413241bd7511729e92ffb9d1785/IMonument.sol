// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IMonument {
  function mintFor(
    address _for,
    uint256 _id,
    uint256 _amount
  ) external;

  function mintBatchFor(
    address _for,
    uint256[] calldata _ids,
    uint256[] calldata _amounts
  ) external;

  function burn(uint256 _id, uint256 _amount) external;

  function burnBatch(uint256[] calldata ids, uint256[] calldata amounts)
    external;
}

