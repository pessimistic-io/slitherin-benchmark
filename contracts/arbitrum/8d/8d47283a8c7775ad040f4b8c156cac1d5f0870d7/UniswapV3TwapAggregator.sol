// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import { OracleLibrary } from "./OracleLibrary.sol";
import { LiquidityAmounts } from "./LiquidityAmounts.sol";
import { TickMath } from "./TickMath.sol";

import { IERC20Metadata } from "./IERC20Metadata.sol";
import { SafeOwnable } from "./SafeOwnable.sol";

import { Registry } from "./Registry.sol";

import { IValioCustomAggregator } from "./IValioCustomAggregator.sol";
import { IAggregatorV3Interface } from "./IAggregatorV3Interface.sol";

contract UniswapV3TWAPAggregator is SafeOwnable, IValioCustomAggregator {
    struct V3PoolConfig {
        IUniswapV3Pool pool;
        address pairToken;
    }

    Registry public immutable VALIO_REGISTRY;
    // Number of seconds in the past from which to calculate the time-weighted means
    uint32 public immutable SECONDS_AGO;
    // Configure on a per chain basis, based on number of blocks per minute
    uint public immutable CARDINALITY_PER_MINUTE;

    mapping(address => V3PoolConfig) public assetToV3PoolConfig;

    constructor(
        address _VALIO_REGISTRY,
        uint32 _SECONDS_AGO,
        uint _CARDINALITY_PER_MINUTE
    ) {
        _setOwner(msg.sender);
        VALIO_REGISTRY = Registry(_VALIO_REGISTRY);
        SECONDS_AGO = _SECONDS_AGO;
        CARDINALITY_PER_MINUTE = _CARDINALITY_PER_MINUTE;
    }

    function setV3Pool(address asset, IUniswapV3Pool pool) external onlyOwner {
        _assertCardinality(pool);

        address pairToken = pool.token0();
        if (asset == pairToken) {
            pairToken = pool.token1();
        }
        // Must have a chainlink aggregator for the pairedToken
        require(
            address(VALIO_REGISTRY.chainlinkV3USDAggregators(pairToken)) !=
                address(0),
            'no pair aggregator'
        );

        assetToV3PoolConfig[asset] = V3PoolConfig(pool, pairToken);

        // Make a call to check the pool is valid
        (int answer, ) = _latestRoundData(asset);
        require(answer > 0, 'invalid answer');
    }

    /// @notice Helper to prepare cardinatily
    function prepareCardinality(IUniswapV3Pool pool) external {
        // We add 1 just to be on the safe side
        uint16 cardinality = uint16(
            (SECONDS_AGO * CARDINALITY_PER_MINUTE) / 60
        ) + 1;
        IUniswapV3Pool(pool).increaseObservationCardinalityNext(cardinality);
    }

    function latestRoundData(
        address mainToken
    ) external view override returns (int256 answer, uint256 updatedAt) {
        return _latestRoundData(mainToken);
    }

    function getHarmonicMeanLiquidity(
        address mainToken
    ) external view returns (uint256 harmonicMeanLiquidity) {
        V3PoolConfig memory v3PoolConfig = assetToV3PoolConfig[mainToken];

        (, harmonicMeanLiquidity) = OracleLibrary.consult(
            address(v3PoolConfig.pool),
            SECONDS_AGO
        );
    }

    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function description() external pure override returns (string memory) {
        return 'UniswapV3TWAPAggregator';
    }

    function _requiredCardinality() internal view returns (uint16) {
        return uint16((SECONDS_AGO * CARDINALITY_PER_MINUTE) / 60) + 1;
    }

    function _assertCardinality(IUniswapV3Pool pool) internal view {
        (, , , , uint16 observationCardinality, , ) = pool.slot0();
        uint16 requiredCardinality = _requiredCardinality();
        require(
            observationCardinality >= requiredCardinality,
            'Cardinality not prepared'
        );
    }

    /// @notice Get the latest price from the twap
    /// @return answer The price 10**8
    /// @return updatedAt Timestamp of when the pair token was last updated.
    function _latestRoundData(
        address mainToken
    ) internal view returns (int256 answer, uint256 updatedAt) {
        V3PoolConfig memory v3PoolConfig = assetToV3PoolConfig[mainToken];
        address pairToken = v3PoolConfig.pairToken;
        IAggregatorV3Interface pairTokenUsdAggregator = VALIO_REGISTRY
            .chainlinkV3USDAggregators(pairToken);

        uint mainTokenUnit = 10 ** IERC20Metadata(mainToken).decimals();

        uint pairTokenUnit = 10 ** IERC20Metadata(pairToken).decimals();

        (int24 tick, uint128 harmonicMeanLiquidity) = OracleLibrary.consult(
            address(v3PoolConfig.pool),
            SECONDS_AGO
        );

        require(harmonicMeanLiquidity > 0, 'NLQ');

        uint256 quoteAmount = OracleLibrary.getQuoteAtTick(
            tick,
            uint128(mainTokenUnit),
            mainToken,
            pairToken
        );

        int256 pairUsdPrice;
        (, pairUsdPrice, , updatedAt, ) = pairTokenUsdAggregator
            .latestRoundData();

        answer = (pairUsdPrice * int256(quoteAmount)) / int256(pairTokenUnit);

        return (answer, updatedAt);
    }
}

