// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;

// ====================================================================
// ========================= UniV3TWAPOracle ==========================
// ====================================================================

// Wraps the in-built UniV3 pool's oracle with the Chainlink-style interface

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

import "./AggregatorV3Interface.sol";
import "./IUniswapV3Pool.sol";
import "./OracleLibrary.sol";
import "./Owned.sol";
import "./IERC20Metadata.sol";

contract UniV3TWAPOracle is Owned {
    // Core
    IUniswapV3Pool public pool;
    IERC20Metadata public base_token;
    IERC20Metadata public pricing_token;

    // AggregatorV3Interface stuff
    string public description = "Uniswap TWA Oracle";
    uint256 public version = 1;

    // Misc
    uint32 public lookback_secs = 300; // 5 minutes

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

    // In E18
    function getPrecisePrice() public view returns (uint256 amount_out) {
        // Get the average price tick first
        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(
            address(pool),
            lookback_secs
        );

        // Get the quote for selling 1 unit of a token.
        amount_out = OracleLibrary.getQuoteAtTick(
            arithmeticMeanTick,
            uint128(10**pricing_token.decimals()),
            address(pricing_token),
            address(base_token)
        );
    }

    // In E6
    function getPrice() public view returns (uint256) {
        return getPrecisePrice(); // USDC per SWEEP
    }

    // AggregatorV3Interface / Chainlink compatibility
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, int256(getPrecisePrice()), 0, block.timestamp, 0);
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

    // Convenience function
    function increaseObservationCardinality(uint16 _num_cardinals)
        external
        onlyAdmin
    {
        pool.increaseObservationCardinalityNext(_num_cardinals);
    }

    function setTWAPLookbackSec(uint32 _secs) external onlyAdmin {
        lookback_secs = _secs;
    }

    function toggleTokenForPricing() external onlyAdmin {
        IERC20Metadata aux = base_token;
        base_token = pricing_token;
        pricing_token = aux;
    }
}

