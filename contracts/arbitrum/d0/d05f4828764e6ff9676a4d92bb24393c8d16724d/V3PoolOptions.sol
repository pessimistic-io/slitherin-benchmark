// SPDX-License-Identifier: None
pragma solidity ^0.8.18;

import {EnumerableSet} from "./EnumerableSet.sol";

import {TickMath} from "./TickMath.sol";
import {FullMath} from "./FullMath.sol";
import {AlcorUtils} from "./AlcorUtils.sol";

import {VanillaOptionPool} from "./VanillaOptionPool.sol";

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IV3PoolOptions} from "./IV3PoolOptions.sol";

import {console} from "./console.sol";

abstract contract V3PoolOptions is IV3PoolOptions {
    error expired();
    error notYetExpired();
    error notAvailableExpiry();
    error expiryNotExists();
    //
    error notApprovedComboContract();
    error optionPoolAlreadyExists();
    error zeroAddress();
    error poolNotExists();

    using EnumerableSet for EnumerableSet.UintSet;
    using VanillaOptionPool for VanillaOptionPool.Key;
    using VanillaOptionPool for mapping(bytes32 vaillaOptionPoolHash => VanillaOptionPool.PoolBalance);

    event OptionExpired(uint256 price);

    // responsible for the duration of the TWAP when the option pool becomes expired
    uint32 constant TWAP_DURATION = 1000;
    // this variable is used to get the average underlying price
    uint32 constant SWAP_TWAP_DURATION = 65000;

    // this mapping defines the parameters of initialized option pool
    mapping(bytes32 optionPoolKeyHash => VanillaOptionPool.Key)
        public optionPoolKeyStructs;

    // options table
    mapping(bool isCall => EnumerableSet.UintSet) private availableExpiries;
    mapping(bool isCall => mapping(uint256 expiry => EnumerableSet.UintSet))
        private availableStrikes;
    mapping(bytes32 vaillaOptionPoolHash => VanillaOptionPool.PoolBalance)
        public
        override poolsBalances;

    mapping(uint256 expiry => uint256 assetPriceAtExpiry)
        public pricesAtExpiries;

    mapping(address contractAddress => bool approved)
        public isApprovedComboContract;
    address[] public approvedComboContracts;

    IUniswapV3Pool public immutable realUniswapV3Pool;
    int16 public immutable realPoolTokensDeltaDecimals;

    constructor(address _realUniswapV3PoolAddr) {
        realUniswapV3Pool = IUniswapV3Pool(_realUniswapV3PoolAddr);
        realPoolTokensDeltaDecimals = AlcorUtils.getDeltaDecimalsToken1Token0(
            realUniswapV3Pool
        );
    }

    function _updatePoolBalances(
        bytes32 optionPoolKeyHash,
        int256 token0Delta,
        int256 token1Delta
    ) internal {
        poolsBalances.updatePoolBalances(
            optionPoolKeyHash,
            token0Delta,
            token1Delta
        );
    }

    function getAvailableExpiries(
        bool isCall
    ) external view returns (uint256[] memory expiries) {
        expiries = availableExpiries[isCall].values();
    }

    function getAvailableStrikes(
        uint256 expiry,
        bool isCall
    ) external view returns (uint256[] memory strikes) {
        strikes = availableStrikes[isCall][expiry].values();
    }

    // @dev updates the sets of available expiries and strikes (for call or put option type)
    function _addExpiryAndStrike(
        VanillaOptionPool.Key memory optionPoolKey
    ) private {
        availableExpiries[optionPoolKey.isCall].add(optionPoolKey.expiry);
        availableStrikes[optionPoolKey.isCall][optionPoolKey.expiry].add(
            optionPoolKey.strike
        );
    }

    function checkNotExpired(uint256 expiry) internal view {
        if (pricesAtExpiries[expiry] != 0) revert expired();
    }

    function _addOptionPool(
        uint256 expiry,
        uint256 strike,
        bool isCall
    ) internal returns (bytes32 optionPoolKeyHash) {
        VanillaOptionPool.Key memory optionPoolKey = VanillaOptionPool.Key({
            expiry: expiry,
            strike: strike,
            isCall: isCall
        });
        optionPoolKeyHash = optionPoolKey.hashOptionPool();
        // console.log("optionPoolKeyHash");
        // console.logBytes32(optionPoolKeyHash);

        // update the mapping
        optionPoolKeyStructs[optionPoolKeyHash] = optionPoolKey;
        _addExpiryAndStrike(optionPoolKey);
    }

    // @dev wrapper
    function _blockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp);
    }

    function _addComboOption(address comboOptionAddress) internal {
        isApprovedComboContract[comboOptionAddress] = true;
        approvedComboContracts.push(comboOptionAddress);
    }

    // @dev stores the price at the expiry
    function _toExpiredState(uint256 expiry) internal {
        if (
            !availableExpiries[false].contains(expiry) &&
            !availableExpiries[true].contains(expiry)
        ) revert expiryNotExists();
        if (expiry > _blockTimestamp()) revert notYetExpired();
        if (pricesAtExpiries[expiry] != 0) revert expired();

        int24 twap = AlcorUtils.getTwap(realUniswapV3Pool, TWAP_DURATION);
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(twap);
        uint256 price = FullMath.mulDiv(
            1e18,
            1e18,
            AlcorUtils.sqrtPriceX96ToUint(
                sqrtPriceX96,
                realPoolTokensDeltaDecimals
            )
        );

        pricesAtExpiries[expiry] = price;

        console.log("twap:");
        console.logInt(twap);

        console.log("realPoolTokensDeltaDecimals");
        console.logInt(realPoolTokensDeltaDecimals);

        console.log("price at expiry");
        console.log(price);

        emit OptionExpired(price);
    }
}

