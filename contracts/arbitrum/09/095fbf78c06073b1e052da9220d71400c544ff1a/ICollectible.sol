// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface ICollectible {
  function mintFor(
    address _for,
    uint256 _id,
    uint256 _amount
  ) external;

  function mintBatchFor(
    address _for,
    uint256[] memory _ids,
    uint256[] memory _amounts
  ) external;

  function burn(uint256 _id, uint256 _amount) external;

  function burnBatch(uint256[] memory ids, uint256[] memory amounts) external;
}

