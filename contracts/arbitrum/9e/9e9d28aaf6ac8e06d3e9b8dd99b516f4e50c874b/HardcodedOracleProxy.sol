// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IOracleProxy} from "./IOracleProxy.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {TickMath} from "./TickMath.sol";
import {Errors} from "./Errors.sol";

/**
 * @title HardcodedOracleProxy v1.1
 * @author Tazz Labs
 * @notice Implements the logic to read prices for nonrebasing tokens
 **/

contract HardcodedOracleProxy is IOracleProxy {
    using WadRayMath for uint256;

    address public immutable TOKEN0;
    address public immutable TOKEN1;
    address public immutable ORACLE_SOURCE;
    int24 public TICK_VALUE;

    /**
     * @notice Initializes a TazzPriceOracle structure
     * @param tokenA The address of tokenA
     * @param tokenB The address of tokenB
     * @param tickValue The hardcoded tick value of tokenB / tokenA
     **/
    constructor(
        address tokenA,
        address tokenB,
        int24 tickValue
    ) {
        // Set values
        TOKEN0 = (tokenA < tokenB) ? tokenA : tokenB;
        TOKEN1 = (tokenA < tokenB) ? tokenB : tokenA;
        TICK_VALUE = (tokenA < tokenB) ? tickValue : -tickValue;
        ORACLE_SOURCE = address(0);
    }

    // Get base currency address given asset address
    function getBaseCurrency(address asset) external view returns (address) {
        require(asset == TOKEN0 || asset == TOKEN1, Errors.ORACLE_ASSET_MISMATCH);
        if (asset == TOKEN0) {
            return TOKEN1;
        } else {
            return TOKEN0;
        }
    }

    // Fetches twap for asset in base currency terms
    function getAvgTick(address asset, uint32 lookbackPeriod) external view returns (int24 avgTick_) {
        // @dev The lookbackPeriod parameter is not used in this implementation.
        // The special comment below is to silence the compiler warning about an unused variable.
        lookbackPeriod;

        require((asset == TOKEN0 || asset == TOKEN1), Errors.ORACLE_ASSET_MISMATCH);
        // Get ticks from ankrETH rate
        if (asset == TOKEN1){
            return TICK_VALUE;
        } else {
            return -TICK_VALUE;
        }
    }
}

