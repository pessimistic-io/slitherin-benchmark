// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;

// ====================================================================
// ========================= UniV3TWAPOracle ==========================
// ====================================================================

// Wraps the in-built UniV3 pool's oracle with the Chainlink-style interface

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

import "./SafeMath.sol";
import "./IUniswapV3Pool.sol";
import "./OracleLibrary.sol";
import "./FullMath.sol";
import "./FixedPoint128.sol";
import "./Owned.sol";
import "./IERC20Metadata.sol";

contract UniV3TWAPOracle is Owned {
    using SafeMath for uint256;

    // Core
    IUniswapV3Pool public pool;
    IERC20Metadata public base_token;
    IERC20Metadata public pricing_token;

    // AggregatorV3Interface stuff
    string public description = "Uniswap Oracle";
    uint256 public version = 1;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _sweep_address, 
        address _pool_address
    ) Owned(_sweep_address) {
        _setUniswapPool(_pool_address);
    }

    /* ========== VIEWS ========== */

    function token_symbols()
        external
        view
        returns (string memory base, string memory pricing)
    {
        base = base_token.symbol();
        pricing = pricing_token.symbol();
    }

    function getLiquidity() 
        public
        view
        returns (uint256 sweep_amount, uint256 usdx_amount) 
    {
        (uint128 sweep_fee_Amount, uint128 usdx_fee_amount) = getUnclaimedFeeAmount();
        return (
            IERC20Metadata(pricing_token).balanceOf(address(pool)) - uint256(sweep_fee_Amount),
            IERC20Metadata(base_token).balanceOf(address(pool)) - uint256(usdx_fee_amount)
        );
    }

    function getUnclaimedFeeAmount()
        public 
        view
        returns (uint128 sweep_amount, uint128 usdx_amount) 
    {
        uint256 global0FeeAmount;
        uint256 global1FeeAmount;

        if (pool.token0() == address(base_token)) {
            global0FeeAmount = pool.feeGrowthGlobal0X128();
            global1FeeAmount = pool.feeGrowthGlobal1X128();
        } else {
            global0FeeAmount = pool.feeGrowthGlobal1X128();
            global1FeeAmount = pool.feeGrowthGlobal0X128();
        }

        usdx_amount =
            uint128(
                FullMath.mulDiv(
                    global0FeeAmount,
                    pool.liquidity(),
                    FixedPoint128.Q128
                )
            );

        sweep_amount =
            uint128(
                FullMath.mulDiv(
                    global1FeeAmount,
                    pool.liquidity(),
                    FixedPoint128.Q128
                )
            );
    }

    function getPrice() public view returns (uint256 amount_out) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        // Get the quote for selling 1 unit of a token.
        amount_out = getQuote(
            sqrtRatioX96,
            uint128(10**pricing_token.decimals()),
            address(pricing_token),
            address(base_token)
        );
    }

    function getQuote(
        uint160 sqrtRatioX96,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) public pure returns (uint256 quoteAmount) {
        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    function getPegAmountsForInvest() public view returns (uint256 amount) {
        uint256 sweep_amount = pricing_token.balanceOf(address(pool));
        uint256 usdx_amount = base_token.balanceOf(address(pool));
        uint256 target_price = SWEEP.target_price();
        uint256 radicand = ((sweep_amount / target_price )/1e6) * usdx_amount;
        uint256 root = radicand.sqrt();

        uint256 sweep_to_peg = (root > usdx_amount) ? (root - usdx_amount) : (usdx_amount - root);
        sweep_to_peg = sweep_to_peg * 997 / 1000;

        (, int24 tickCurrent, , , , , ) = pool.slot0();

        amount = OracleLibrary.getQuoteAtTick(tickCurrent, uint128(sweep_to_peg), address(base_token), address(pricing_token));
    }

    function getPegAmountsForCall() public view returns (uint256 amount) {
        uint256 sweep_amount = pricing_token.balanceOf(address(pool));
        uint256 usdx_amount = base_token.balanceOf(address(pool));
        uint256 target_price = SWEEP.target_price();
        uint256 radicand = target_price * sweep_amount * usdx_amount * 1e6;
        uint256 root = radicand.sqrt();

        uint256 sweep_to_peg = (root > sweep_amount) ? (root - sweep_amount) : (sweep_amount - root);
        sweep_to_peg = sweep_to_peg * 997 / 1000;

        (, int24 tickCurrent, , , , , ) = pool.slot0();

        amount = OracleLibrary.getQuoteAtTick(tickCurrent, uint128(sweep_to_peg), address(pricing_token), address(base_token));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function _setUniswapPool(address _pool_address) internal {
        pool = IUniswapV3Pool(_pool_address);
        base_token = IERC20Metadata(pool.token0());
        pricing_token = IERC20Metadata(pool.token1());
    }

    function setUniswapPool(address _pool_address) public onlyAdmin {
        _setUniswapPool(_pool_address);
    }

    function toggleTokenForPricing() external onlyAdmin {
        IERC20Metadata aux = base_token;
        base_token = pricing_token;
        pricing_token = aux;
    }
}

