// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import {TickMath} from "./TickMath.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {OracleLibrary} from "./OracleLibrary.sol";
import {IRamsesV2Pool} from "./IRamsesV2Pool.sol";
import {IERC20} from "./IERC20.sol";
import {IICHIVaultFactory} from "./IICHIVaultFactory.sol";
import {SafeMath} from "./SafeMath.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Strings} from "./Strings.sol";

library UV3Math {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 internal constant PRECISION = 10**18;
    address internal constant NULL_ADDRESS = address(0);

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /*******************
     * Tick Math
     *******************/
    
    function getSqrtRatioAtTick(
        int24 currentTick
    ) public pure returns(uint160 sqrtPriceX96) {
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(currentTick);
    }

    /*******************
     * LiquidityAmounts
     *******************/

    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) public pure returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity);
    }

    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) public pure returns (uint128 liquidity) {
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            amount0,
            amount1);
    }

    /*******************
     * OracleLibrary
     *******************/

    function consult(
        address _pool, 
        uint32 _twapPeriod
    ) public view returns(int24 timeWeightedAverageTick) {
        (timeWeightedAverageTick, ) = OracleLibrary.consult(_pool, _twapPeriod);
    }

    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) public pure returns (uint256 quoteAmount) {
        quoteAmount = OracleLibrary.getQuoteAtTick(tick, baseAmount, baseToken, quoteToken);
    }

    /*******************
     * SafeUnit128
     *******************/

    /// @notice Cast a uint256 to a uint128, revert on overflow
    /// @param y The uint256 to be downcasted
    /// @return z The downcasted integer, now type uint128
    function toUint128(uint256 y) public  pure returns (uint128 z) {
        require((z = uint128(y)) == y, "SafeUint128: overflow");
    }

    /******************************
     * ICHIVault specific functions
     ******************************/

    /**
     @notice Checks if the last price change happened in the current block
     @param pool underlying pool address
     */
    function checkHysteresis(address pool) public view returns(bool) {
        (, , uint16 observationIndex, , , , ) = IRamsesV2Pool(pool).slot0();
        (uint32 blockTimestamp, , , ,) = IRamsesV2Pool(pool).observations(observationIndex);
        return( block.timestamp != blockTimestamp );
    }

    /**
     @dev Computes a unique vault's symbol for vaults created through Ramses factory.
     @param value index of the vault to be created
     */
    function computeIVsymbol(uint256 value) public pure returns (string memory) {
        return string(abi.encodePacked("IV-", Strings.toString(value), "-RAM"));
    }

    /**
     @notice Sends portion of swap fees to feeRecipient and affiliate.
     @param fees0 fees for token0
     @param fees1 fees for token1
     @param affiliate affiliate address
     @param ichiVaultFactory ICHI vaults factory address
     @param token0 token0 address
     @param token1 token1 address
     */
    function distributeFees(
        uint256 fees0, 
        uint256 fees1,
        address affiliate,
        address ichiVaultFactory,
        address token0,
        address token1
    ) public {
        uint256 baseFee = IICHIVaultFactory(ichiVaultFactory).baseFee();
        // if there is no affiliate 100% of the baseFee should go to feeRecipient
        uint256 baseFeeSplit = (affiliate == NULL_ADDRESS)
            ? PRECISION
            : IICHIVaultFactory(ichiVaultFactory).baseFeeSplit();
        address feeRecipient = IICHIVaultFactory(ichiVaultFactory).feeRecipient();

        require(baseFee <= PRECISION, "IV.rebalance: fee must be <= 10**18");
        require(baseFeeSplit <= PRECISION, "IV.rebalance: split must be <= 10**18");
        require(feeRecipient != NULL_ADDRESS, "IV.rebalance: zero address");

        if (baseFee > 0) {
            if (fees0 > 0) {
                uint256 totalFee = fees0.mul(baseFee).div(PRECISION);
                uint256 toRecipient = totalFee.mul(baseFeeSplit).div(PRECISION);
                uint256 toAffiliate = totalFee.sub(toRecipient);
                IERC20(token0).safeTransfer(feeRecipient, toRecipient);
                if (toAffiliate > 0) {
                    IERC20(token0).safeTransfer(affiliate, toAffiliate);
                }
            }
            if (fees1 > 0) {
                uint256 totalFee = fees1.mul(baseFee).div(PRECISION);
                uint256 toRecipient = totalFee.mul(baseFeeSplit).div(PRECISION);
                uint256 toAffiliate = totalFee.sub(toRecipient);
                IERC20(token1).safeTransfer(feeRecipient, toRecipient);
                if (toAffiliate > 0) {
                    IERC20(token1).safeTransfer(affiliate, toAffiliate);
                }
            }
        }
    }

}


