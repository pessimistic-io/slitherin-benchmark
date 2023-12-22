// SPDX-License-Identifier: None
pragma solidity >=0.5.0;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";

interface IBaseAlcorPool {
    struct LPPosition {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 deposit_amount0;
        uint256 deposit_amount1;
        bool isOpen;
    }

    function containsBytes32(address owner, bytes32 _value) external view returns (bool);

    function totalBytes32Values(address owner) external view returns (uint256);

    function getBytes32AtIndex(address owner, uint256 index) external view returns (bytes32);

    function getAllBytes32Values(address owner) external view returns (bytes32[] memory);

    function realUniswapV3Pool() external view returns (IUniswapV3Pool);

    function uniswapV3Pool() external view returns (IUniswapV3Pool);

    function isExpired() external view returns (bool);

    function isCall() external view returns (bool);

    function expiry() external view returns (uint256);

    function strikePrice() external view returns (uint256);

    function tokensDeltaDecimals() external view returns (int16);

    // function sqrtPriceX96ToUint(uint160 sqrtPriceX96, uint8 deltaDecimals) external pure returns (uint256);

    function getDeltaDecimalsToken1Token0() external view returns (int16);

    // function getLPPositionInfo(bytes32 key) external view returns (LPPosition memory);

    function collectProtocolFees(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    // function getUserPositions(address owner) external view returns (bytes32[] memory);

    // function deposit(bytes32 key) external view returns (uint256 amount0, uint256 amount1);
}

