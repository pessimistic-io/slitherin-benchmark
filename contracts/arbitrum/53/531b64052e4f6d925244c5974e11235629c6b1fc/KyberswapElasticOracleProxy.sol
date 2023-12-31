// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./console.sol";
import {IOracleProxy} from "./IOracleProxy.sol";
import {IPool} from "./IPool.sol";
import {IPoolOracle} from "./IPoolOracle.sol";
import {OracleLibrary} from "./OracleLibrary.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {Errors} from "./Errors.sol";

/**
 * @title KyberswapElasticOracleProxy v1.1
 * @author Tazz Labs
 * @notice Implements the logic to read twap prices from Uniswap V3 Dexs
 **/

contract KyberswapElasticOracleProxy is IOracleProxy {
    using WadRayMath for uint256;

    address public immutable TOKEN0;
    address public immutable TOKEN1;
    address public immutable ORACLE_SOURCE;

    address public immutable POOL_ORACLE;
    uint16 public _minCardinality;

    /**
     * @notice Initializes a TazzPriceOracle structure
     * @param tokenA The address of one token in the oracle pair
     * @param tokenB The address of the other token in the oracle pair
     * @param oracleSource The address of the oracle price source
     * @param poolOracle The address of kyberswap pool oracle
     * @param minCardinality The cardinality for dex observations
     **/
    constructor(
        address tokenA,
        address tokenB,
        address oracleSource,
        address poolOracle,
        uint16 minCardinality
    ) {
        // Steps: Check to make sure dex is correct + Adjust cardinality
        address token0_ = address(IPool(oracleSource).token0());
        address token1_ = address(IPool(oracleSource).token1());
        require(
            (token0_ == tokenA && token1_ == tokenB) || (token1_ == tokenA && token0_ == tokenB),
            Errors.DEX_POOL_DOES_NOT_CONTAIN_ASSET_PAIR
        );

        // Increase observation cardinality
        require(minCardinality > 0, Errors.ORACLE_CARDINALITY_IS_ZERO);
        IPoolOracle(poolOracle).increaseObservationCardinalityNext(oracleSource, minCardinality);

        // Set values
        TOKEN0 = (tokenA < tokenB) ? tokenA : tokenB;
        TOKEN1 = (tokenA < tokenB) ? tokenB : tokenA;
        require(TOKEN0 < TOKEN1, Errors.ORACLE_PROXY_TOKENS_NOT_SET_PROPERLY); // for good measure
        ORACLE_SOURCE = oracleSource;
        POOL_ORACLE = poolOracle;
        _minCardinality = minCardinality;
    }

    // Get base currency address given asset address
    function getBaseCurrency(address asset) external view returns (address){
        if (asset == TOKEN0){
            return TOKEN1;
        } else {
            return TOKEN0;
        }
    }

    // Get avg tick function based on uni v3 logic
    function getAvgTick(address asset, uint32 lookbackPeriod) external view returns (int24 avgTick_) {
        // Make sure the oracle contains the asset
        address token0_ = address(IPool(ORACLE_SOURCE).token0());
        address token1_ = address(IPool(ORACLE_SOURCE).token1());
        require((asset == token0_ || asset == token1_), Errors.ORACLE_ASSET_MISMATCH);
        
        // Check farthest lookback period for pool
        uint32 _secondsAgo = OracleLibrary.getOldestObservationSecondsAgo(POOL_ORACLE, ORACLE_SOURCE);
        if (_secondsAgo > lookbackPeriod) {
            _secondsAgo = lookbackPeriod;
        }

        avgTick_ = OracleLibrary.consult(POOL_ORACLE, ORACLE_SOURCE, _secondsAgo);

        // check the tokens for address sort order, and ensure in right order
        // so that cumulative tick can be added together
        address baseCurrency_ = (TOKEN0 == asset) ? TOKEN1 : TOKEN0;
        if (baseCurrency_ < asset) avgTick_ = -avgTick_;
    }

    // Increase pool cardinality
    function increaseDexCardinality(uint16 minCardinality) external {
        require(minCardinality > _minCardinality, Errors.ORACLE_CARDINALITY_MONOTONICALLY_INCREASES);
        _minCardinality = minCardinality;
        IPoolOracle(POOL_ORACLE).increaseObservationCardinalityNext(ORACLE_SOURCE, _minCardinality);
    }
    
    // Get pool cardinality
    function getDexCardinality() external view returns(uint16) {
        return _minCardinality;
    }
}

