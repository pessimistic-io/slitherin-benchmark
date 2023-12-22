// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IBatchBurnableStaker {
  function stakeBatchFor(
    address _staker,
    address _addr,
    uint256[] calldata _realmIds,
    uint256[] calldata _ids,
    uint256[] calldata _amounts
  ) external;

  function unstakeBatchFor(
    address _staker,
    address _addr,
    uint256[] calldata _realmIds,
    uint256[] calldata _ids,
    uint256[] calldata _amounts
  ) external;

  function burnBatchFor(
    address _addr,
    uint256[] calldata _realmIds,
    uint256[] calldata _ids,
    uint256[] calldata _amounts
  ) external;

  function hasStaked(
    uint256 _realmId,
    address _addr,
    uint256 _id,
    uint256 _count
  ) external view returns (bool);

  function stakerBalance(
    uint256 _realmId,
    address _addr,
    uint256 _id
  ) external view returns (uint256);
}

