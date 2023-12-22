// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IOneInchRouterV5 {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    function swap(
        address,
        SwapDescription calldata _desc,
        bytes calldata,
        bytes calldata
    ) external returns (uint256 returnAmount, uint256 spentAmount);

    //already restrict recipient must be msg.sender in 1inch contract
    function unoswap(
        address _srcToken,
        uint256,
        uint256,
        uint256[] calldata pools
    ) external returns (uint256 returnAmount);

    function unoswapTo(
        address recipient,
        address srcToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external returns (uint256 returnAmount);

    function uniswapV3Swap(uint256 amount, uint256 minReturn, uint256[] calldata pools) external;

    function uniswapV3SwapTo(
        address recipient,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external returns (uint256 returnAmount);

    // Safe is the taker.
    struct Order {
        uint256 salt;
        address makerAsset; // For safe to buy
        address takerAsset; // For safe to sell
        address maker;
        address receiver; // Where to send takerAsset, default zero means sending to maker.
        address allowedSender; // equals to Zero address on public orders
        uint256 makingAmount;
        uint256 takingAmount;
        uint256 offsets;
        bytes interactions; // concat(makerAssetData, takerAssetData, getMakingAmount, getTakingAmount, predicate, permit, preIntercation, postInteraction)
    }

    function fillOrder(
        Order calldata order,
        bytes calldata signature,
        bytes calldata interaction,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 skipPermitAndThresholdAmount
    ) external returns (uint256 actualMakingAmount, uint256 actualTakingAmount, bytes32 orderHash);

    function fillOrderTo(
        Order calldata order_,
        bytes calldata signature,
        bytes calldata interaction,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 skipPermitAndThresholdAmount,
        address target
    ) external returns (uint256 actualMakingAmount, uint256 actualTakingAmount, bytes32 orderHash);

    struct OrderRFQ {
        uint256 info; // lowest 64 bits is the order id, next 64 bits is the expiration timestamp
        address makerAsset;
        address takerAsset;
        address maker;
        address allowedSender; // equals to Zero address on public orders
        uint256 makingAmount;
        uint256 takingAmount;
    }

    function fillOrderRFQ(
        OrderRFQ calldata order,
        bytes calldata signature,
        uint256 flagsAndAmount
    ) external returns (uint256 /* filledMakingAmount */, uint256 /* filledTakingAmount */, bytes32 /* orderHash */);

    function fillOrderRFQTo(
        OrderRFQ memory order,
        bytes calldata signature,
        uint256 flagsAndAmount,
        address target
    ) external payable returns (uint256 filledMakingAmount, uint256 filledTakingAmount, bytes32 orderHash);

    function fillOrderRFQCompact(
        OrderRFQ calldata order,
        bytes32 r,
        bytes32 vs,
        uint256 flagsAndAmount
    ) external returns (uint256 filledMakingAmount, uint256 filledTakingAmount, bytes32 orderHash);

    function clipperSwap(
        address clipperExchange,
        address srcToken,
        address dstToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 goodUntil,
        bytes32 r,
        bytes32 vs
    ) external returns (uint256 returnAmount);

    function clipperSwapTo(
        address clipperExchange,
        address recipient,
        address srcToken,
        address dstToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 goodUntil,
        bytes32 r,
        bytes32 vs
    ) external returns (uint256 returnAmount);
}

