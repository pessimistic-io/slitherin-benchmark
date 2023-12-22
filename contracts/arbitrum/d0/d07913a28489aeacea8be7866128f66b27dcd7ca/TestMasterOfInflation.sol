// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IMasterOfInflation.sol";

contract TestMasterOfInflation is IMasterOfInflation {
  mapping(uint64 => uint256) chances;

  function setChance(uint64 _poolId, uint256 _chance) external {
    chances[_poolId] = _chance;
  }

  function chanceOfItemFromPool(
    uint64 _poolId,
    uint64 _amount,
    uint32 _bonus,
    uint32 _negativeBonus
  ) external view returns (uint256) {
    return chances[_poolId];
  }

  function tryMintFromPool(
    MintFromPoolParams calldata _params
  ) external returns (bool _didMintItem) {
    uint256 rand = _params.randomNumber % 100000;
    return rand < chances[_params.poolId];
  }
}

