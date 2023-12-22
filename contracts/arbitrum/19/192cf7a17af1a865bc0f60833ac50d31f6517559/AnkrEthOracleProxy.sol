// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./console.sol";
import {IOracleProxy} from "./IOracleProxy.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {TickMath} from "./TickMath.sol";
import {Errors} from "./Errors.sol";
import {IERC20Detailed} from "./IERC20Detailed.sol";
import {Math} from "./Math.sol";
import {AnkrETHRateProvider} from "./AnkrETHRateProvider.sol";

/**
 * @title AnkrEthOracleProxy v1.1
 * @author Tazz Labs
 * @notice Implements the logic to read prices for nonrebasing tokens
 **/

contract AnkrEthOracleProxy is IOracleProxy {
    using WadRayMath for uint256;

    address public immutable TOKEN0;
    address public immutable TOKEN1;
    address public immutable ORACLE_SOURCE;

    /**
     * @notice Initializes a TazzPriceOracle structure
     * @param tokenA The address of one token in the oracle pair
     * @param tokenB The address of the other token in the oracle pair
     * @param oracleSource The address of the oracle price source
     **/
    constructor(
        address tokenA,
        address tokenB,
        address oracleSource
    ) {
        // Check to make sure oracle price source is correct
        AnkrETHRateProvider ankrETHProvider = AnkrETHRateProvider(oracleSource);
        address ankrETH = ankrETHProvider.ankrETH();
        require((ankrETH == tokenA || ankrETH == tokenB), Errors.ORACLE_ASSET_MISMATCH);
        
        // Set values
        TOKEN0 = (tokenA < tokenB) ? tokenA : tokenB;
        TOKEN1 = (tokenA < tokenB) ? tokenB : tokenA;
        require(TOKEN0 < TOKEN1, Errors.ORACLE_PROXY_TOKENS_NOT_SET_PROPERLY); // for good measure
        ORACLE_SOURCE = oracleSource;
    }

    // Get base currency address given asset address
    function getBaseCurrency(address asset) external view returns (address){
        if (asset == TOKEN0){
            return TOKEN1;
        } else {
            return TOKEN0;
        }
    }

    // Fetches twap for asset in base currency terms
    function getAvgTick(address asset, uint32 lookbackPeriod) external view returns (int24 avgTick_) {
        // Get ticks from ankrETH rate
        AnkrETHRateProvider ankrETHRateProvider_ = AnkrETHRateProvider(ORACLE_SOURCE);
        uint256 rate_ = ankrETHRateProvider_.getRate();
        uint160 priceX96 = uint160(79228162514 * rate_); // uint160(2**96 * rate_ / 10**18)
        avgTick_ = TickMath.getTickAtSqrtRatio(priceX96) / 2;
        
        // Adjust rate if asset != ankrETH
        address ankrETH = ankrETHRateProvider_.ankrETH();
        if (asset != ankrETH) {
            avgTick_ = -avgTick_;
        }
    }
}

