//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./IAsset.sol";

// https://docs.balancer.fi/reference/swaps/single-swap.html#swap-function

interface IBalancerVault {
    // function WETH() external view returns (address);

    //BALANCER STRUCT
    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    //BALANCER ENUM
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    //BALANCER STRUCT
    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        IAsset assetIn;
        IAsset assetOut;
        uint256 amount;
        bytes userData;
    }

    // function batchSwap(
    //     uint8 kind,
    //     SingleSwap[] swaps,
    //     address[] assets,
    //     FundManagement funds,
    //     int256[] limits,
    //     uint256 deadline
    // ) external returns (int256[] assetDeltas);

    // function deregisterTokens(bytes32 poolId, address[] tokens) external;

    // // function exitPool(
    // //     bytes32 poolId,
    // //     address sender,
    // //     address recipient,
    // //     tuple request
    // // ) external;

    // function flashLoan(
    //     address recipient,
    //     address[] tokens,
    //     uint256[] amounts,
    //     bytes userData
    // ) external;

    // function getActionId(bytes4 selector) external view returns (bytes32);

    // function getAuthorizer() external view returns (address);

    // function getDomainSeparator() external view returns (bytes32);

    // function getInternalBalance(
    //     address user,
    //     address[] tokens
    // ) external view returns (uint256[] balances);

    // function getNextNonce(address user) external view returns (uint256);

    // function getPausedState()
    //     external
    //     view
    //     returns (
    //         bool paused,
    //         uint256 pauseWindowEndTime,
    //         uint256 bufferPeriodEndTime
    //     );

    function getPool(bytes32 poolId) external view returns (address, uint8);

    function getPoolTokenInfo(
        bytes32 poolId,
        address token
    )
        external
        view
        returns (
            uint256 cash,
            uint256 managed,
            uint256 lastChangeBlock,
            address assetManager
        );

    function getPoolTokens(
        bytes32 poolId
    )
        external
        view
        returns (
            address[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangeBlock
        );

    // function getProtocolFeesCollector() external view returns (address);

    // function hasApprovedRelayer(
    //     address user,
    //     address relayer
    // ) external view returns (bool);

    // function joinPool(
    //     bytes32 poolId,
    //     address sender,
    //     address recipient,
    //     tuple request
    // ) external;

    // function managePoolBalance(tuple[] ops) external;

    // function manageUserBalance(tuple[] ops) external;

    // function queryBatchSwap(
    //     uint8 kind,
    //     SingleSwap[] swaps,
    //     address[] assets,
    //     FundManagement funds
    // ) external returns (int256[]);

    // function registerPool(uint8 specialization) external returns (bytes32);

    // function registerTokens(
    //     bytes32 poolId,
    //     address[] tokens,
    //     address[] assetManagers
    // ) external;

    // function setAuthorizer(address newAuthorizer) external;

    // function setPaused(bool paused) external;

    // function setRelayerApproval(
    //     address sender,
    //     address relayer,
    //     bool approved
    // ) external;

    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external returns (uint256 amountCalculated);
}

//  {
//         pool: "0x4e7f40cd37cee710f5e87ad72959d30ef8a01a5d00010000000000000000000b",
//         tokenIn: "0x2791bca1f2de4661ed88a30c99a7a9449aa84174",
//         tokenOut: "0x7ceb23fd6bc0add59e62ac25578270cff1b9f619",
//         limitReturnAmount: "0",
//         swapAmount: "12154711",
//         amountOut: "7396822524192005",
//         exchange: "balancer",
//         poolLength: 4,
//         poolType: "balancer-weighted",
//         vault: "0xba12222222228d8ba445958a75a0704d566bf2c8",
//       },

