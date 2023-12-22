// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;

// ====================================================================
// ========================= UniV3TWAPOracle ==========================
// ====================================================================

// Wraps the in-built UniV3 pool's oracle with the Chainlink-style interface

// Primary Author(s)
// Che Jin: https://github.com/topdev104

import "./IERC20Metadata.sol";
import "./AggregatorV3Interface.sol";
import "./IUniswapV3Pool.sol";
import "./OracleLibrary.sol";
import "./Owned.sol";

contract UniV3TWAPOracle is Owned {
    // Core
    address public timelock_address;
    IUniswapV3Pool public pool;
    IERC20Metadata public token0;
    IERC20Metadata public token1;

    // AggregatorV3Interface stuff
    uint8 public decimals = 18; // For Chainlink mocking
    string public description = "Uniswap TWA Oracle";
    uint256 public version = 1;

    // Misc
    uint32 public lookback_secs = 300; // 5 minutes
    bool public price_in_token0 = false; // can flip the order of the pricing

    /* ========== MODIFIERS ========== */

    modifier onlyByOwnGov() {
        require(msg.sender == owner || msg.sender == timelock_address, "Not owner or timelock");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor (
        address _creator_address,
        address _timelock_address,
        address _pool_address
    ) Owned(_creator_address) {
        timelock_address = _timelock_address;

        // Core
        pool = IUniswapV3Pool(_pool_address);
        token0 = IERC20Metadata(pool.token0()); // USDC
        token1 = IERC20Metadata(pool.token1()); // SWEEP
        price_in_token0 = true; // USDC per SWEEP

        // Make sure USDC is E6 and SWEEP is E18
        require ((token0.decimals() == 6) && (token1.decimals() == 18), 'Must USDC is E6 and SWEEP is E18');
    }

    /* ========== VIEWS ========== */

    function token_symbols() external view returns (string memory base, string memory pricing) {
        if (price_in_token0) { // USDC per SWEEP
            base = token1.symbol();
            pricing = token0.symbol();
        } else { // SWEEP per USDC
            base = token0.symbol();
            pricing = token1.symbol();
        }
    }

    // In E18
    function getPrecisePrice() public view returns (uint256 amount_out) {
        // Get the average price tick first
        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(address(pool), lookback_secs);

        // Get the quote for selling 1 unit of a token. Assumes 1e18 for both.
        if (price_in_token0) { // USDC per SWEEP
            amount_out = OracleLibrary.getQuoteAtTick(arithmeticMeanTick, 1e18, address(token1), address(token0));
        } else { // SWEEP per USDC
            amount_out = OracleLibrary.getQuoteAtTick(arithmeticMeanTick, 1e6, address(token0), address(token1));
        }
    }

    // In E6
    function getPrice() public view returns (uint256) {
        if (price_in_token0) { // USDC per SWEEP
            return getPrecisePrice();
        } else { // SWEEP per USDC
            return getPrecisePrice() / 1e12;
        }
    }

    // AggregatorV3Interface / Chainlink compatibility
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (0, int256(getPrecisePrice()), 0, block.timestamp, 0);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setTimelock(address _new_timelock_address) external onlyByOwnGov {
        timelock_address = _new_timelock_address;
    }

    // Convenience function
    function increaseObservationCardinality(uint16 _num_cardinals) external onlyByOwnGov {
        pool.increaseObservationCardinalityNext(_num_cardinals);
    }

    function setTWAPLookbackSec(uint32 _secs) external onlyByOwnGov {
        lookback_secs = _secs;
    }

    function toggleTokenForPricing() external onlyByOwnGov {
        price_in_token0 = !price_in_token0;
    }

}
