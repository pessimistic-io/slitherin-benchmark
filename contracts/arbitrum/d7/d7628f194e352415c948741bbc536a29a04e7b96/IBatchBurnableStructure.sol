// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IBatchBurnableStructure {
  function burnBatchFor(
    address _from,
    uint256[] calldata ids,
    uint256[] calldata amounts
  ) external;
}

