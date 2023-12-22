// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

interface IControllerV7 {
  enum Governance {
    devfund,
    treasury,
    strategist,
    governance,
    timelock
  }

  enum Strategy {
    vault,
    revoke,
    approve,
    removeVault,
    removeStrategy,
    setStrategy
  }

  enum Withdraw {
    withdrawAll,
    inCaseTokensGetStuck,
    inCaseStrategyTokenGetStuck,
    withdraw,
    withdrawReward
  }

  function converters(address, address) external view returns (address);

  function earn(
    address _pool,
    uint256 _token0Amount,
    uint256 _token1Amount
  ) external;

  function getLowerTick(address _pool) external view returns (int24);

  function getUpperTick(address _pool) external view returns (int24);

  function governance(uint8) external view returns (address);

  function liquidityOf(address _pool) external view returns (uint256);

  function onERC721Received(
    address,
    address,
    uint256,
    bytes memory
  ) external pure returns (bytes4);

  function strategies(address) external view returns (address);

  function treasury() external view returns (address);

  function vaults(address) external view returns (address);

  function withdraw(address _pool, uint256 _amount) external returns (uint256 a0, uint256 a1);

  function withdrawFunction(
    uint8 name,
    address _pool,
    uint256 _amount,
    address _token
  ) external returns (uint256, uint256);
}

