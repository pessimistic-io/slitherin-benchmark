// SPDX-License-Identifier: None
pragma solidity ^0.8.18;

// import {AlcorUtils} from '../libraries/AlcorUtils.sol';
import {IBaseAlcorOptionCore} from "./IBaseAlcorOptionCore.sol";

import {VanillaOptionPool} from "./VanillaOptionPool.sol";

interface IAlcorOptionCore is IBaseAlcorOptionCore {
    // event OptionExpired(uint256 price);
    event AlcorMint(
        address indexed owner,
        uint256 amount0Delta,
        uint256 amount1Delta
    );
    event AlcorBurn(
        address indexed owner,
        uint256 amount0ToTransfer,
        uint256 amount1ToTransfer
    );
    event AlcorCollect(address indexed owner, uint128 amount0, uint128 amount1);
    event AlcorWithdraw(uint256 payoutAmount);
    event AlcorSwap(address indexed owner, int256 amount0, int256 amount1);
    event AlcorUpdatePosition(
        address indexed owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 newLiquidity
    );
    event AlcorAddOptionPool(
        uint256 indexed expiry,
        uint256 indexed strike,
        bool indexed isCall,
        address conjugatedUniPool
    );
    event AlcorInitOptionPool(
        uint256 indexed expiry,
        uint256 indexed strike,
        bool indexed isCall,
        int24 tick
    );

    function addOptionPool(
        VanillaOptionPool.Key memory optionPoolKey,
        address conjugatedPoolAddr
    ) external;

    function initializeWithTick(
        VanillaOptionPool.Key memory optionPoolKey,
        int24 tick
    ) external;

    function toExpiredState(uint256 expiry) external;

    function preWithdrawChecks(
        VanillaOptionPool.Key memory optionPoolKey
    ) external;

    // function mint(
    //     address owner,
    //     AlcorUtils.OptionPoolInfo memory _optionPoolInfo,
    //     int24 tickLower,
    //     int24 tickUpper,
    //     uint128 amount
    // ) external returns (uint256 amount0Delta, uint256 amount1Delta);

    // function burn(
    //     address owner,
    //     AlcorUtils.OptionPoolInfo memory _optionPoolInfo,
    //     int24 tickLower,
    //     int24 tickUpper,
    //     uint128 amount
    // ) external returns (uint256 amount0ToTransfer, uint256 amount1ToTransfer, int256 userOptionBalanceDelta);

    // function collectFees(
    //     AlcorUtils.OptionPoolInfo memory _optionPoolInfo,
    //     int24 tickLower,
    //     int24 tickUpper
    // ) external returns (uint128 amount0, uint128 amount1);

    // function collectProtocolFees(
    //     AlcorUtils.OptionPoolInfo memory _optionPoolInfo,
    //     address recipient,
    //     uint128 amount0Requested,
    //     uint128 amount1Requested
    // ) external returns (uint128 amount0, uint128 amount1);

    function swap(
        address owner,
        VanillaOptionPool.Key memory optionPoolKey,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external returns (int256 amount0, int256 amount1);

    // function withdraw(address owner, OptionPool.Key memory optionPoolKey) external returns (uint256 amount);
}

