// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; 

library BeefyBalancerStructs {
    enum RouterType {
        BALANCER,
        UNISWAP_V2,
        UNISWAP_V3
    }
    struct BatchSwapStruct {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
    }

    struct Reward {
        RouterType routerType;
        address router;
        mapping(uint => BatchSwapStruct) swapInfo;
        address[] assets;
        bytes routeToNative; // backup route in case there is no Balancer liquidity for reward
        uint minAmount; // minimum amount to be swapped to native
    }

     struct Input {
        address input;
        bool isComposable;
        bool isBeets;
    }
}
