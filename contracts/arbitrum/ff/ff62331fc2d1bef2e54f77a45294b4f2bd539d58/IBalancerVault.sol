// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface IAsset {
  // solhint-disable-previous-line no-empty-blocks
}

interface IBalancerVault {
  enum SwapKind {
    GIVEN_IN,
    GIVEN_OUT
  }

  struct SingleSwap {
    bytes32 poolId;
    SwapKind kind;
    IAsset assetIn;
    IAsset assetOut;
    uint256 amount;
    bytes userData;
  }

  struct FundManagement {
    address sender;
    bool fromInternalBalance;
    address payable recipient;
    bool toInternalBalance;
  }

  enum PoolSpecialization {
    GENERAL,
    MINIMAL_SWAP_INFO,
    TWO_TOKEN
  }

  function getPool(
    bytes32 poolId
  ) external view returns (address, PoolSpecialization);

  function swap(
    SingleSwap memory singleSwap,
    FundManagement memory funds,
    uint256 limit,
    uint256 deadline
  ) external payable returns (uint256);
}

