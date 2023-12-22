// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./IAsset.sol";

enum SwapKind { GIVEN_IN, GIVEN_OUT }

struct BatchSwapStep {
    bytes32 poolId;
    uint256 assetInIndex;
    uint256 assetOutIndex;
    uint256 amount;
    bytes userData;
}

struct FundManagement {
    address sender;
    bool fromInternalBalance;
    address payable recipient;
    bool toInternalBalance;
}

enum PoolSpecialization { GENERAL, MINIMAL_SWAP_INFO, TWO_TOKEN }

struct JoinPoolRequest {
    IAsset[] assets;
    uint256[] maxAmountsIn;
    bytes userData;
    bool fromInternalBalance;
}

struct ExitPoolRequest {
    IAsset[] assets;
    uint256[] minAmountsOut;
    bytes userData;
    bool toInternalBalance;
}

interface IBeets {
    function swapTokens(IAsset[] memory tokens_, BatchSwapStep[] memory batchSwapStep_) external returns(uint256 amountOut);
    function queryBatchSwap(SwapKind kind, BatchSwapStep[] memory swaps, IAsset[] memory assets, FundManagement memory funds) external returns (int256[] memory assetDeltas);
    function batchSwap(SwapKind kind, BatchSwapStep[] memory swaps, IAsset[] memory assets, FundManagement memory funds, int256[] memory limits, uint256 deadline) external payable returns (int256[] memory assetDeltas);
    function getPool(bytes32 poolId) external view returns (address, PoolSpecialization);
    function joinPool(bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request) external payable;
    function exitPool(bytes32 poolId, address sender, address payable recipient, ExitPoolRequest memory request) external;
}
