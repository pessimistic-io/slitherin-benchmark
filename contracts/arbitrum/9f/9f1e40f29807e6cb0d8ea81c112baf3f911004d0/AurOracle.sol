// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";

import "./Babylonian.sol";
import "./FixedPoint.sol";
import "./UniswapV2OracleLibrary.sol";
import "./Epoch.sol";
import "./IUniswapV2Pair.sol";
import "./ChainlinkInterface.sol";

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period

contract AurOracle is Epoch {
    event PriceFeedChanged(address indexed newFeed);

    using FixedPoint for *;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */
    uint256 public PERIOD = 21600; // 6 hour TWAP (time-weighted average price)
    uint256 public CONSULT_LENIENCY = 21600; // Used for being able to consult past the period end
    bool public ALLOW_STALE_CONSULTS = false; // If false, consult() will fail if the TWAP is stale

    AggregatorV3Interface public feed;

    constructor(AggregatorV3Interface _feed, uint256 _period, uint256 _startTime) Epoch(_period, _startTime, 0) {
        require(address(_feed) != address(0), "Oracle: INVALID_FEED");
        feed = _feed;
    }

    function setNewPeriod(uint256 _period) external onlyOperator {
        this.setPeriod(_period);
    }

    function setConsultLeniency(uint256 _consult_leniency) external onlyOperator {
        CONSULT_LENIENCY = _consult_leniency;
    }

    function setAllowStaleConsults(bool _allow_stale_consults) external onlyOperator {
        ALLOW_STALE_CONSULTS = _allow_stale_consults;
    }

    function setNewPriceFeed(AggregatorV3Interface _feed) external onlyOperator {
        require(address(_feed) != address(0), "Oracle: INVALID_FEED");
        feed = _feed;
        emit PriceFeedChanged(address(_feed));
    }

    function canUpdate() public pure returns (bool) {
        return true;
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function update() external checkEpoch {}

    function consult(address, /* _token */ uint256 _amountIn) public view returns (uint144 amountOut) {
        // get price from chainlink feed, lastUpdatedAt and check if it is stale
        (, int256 price,, uint256 lastUpdatedAt,) = feed.latestRoundData();
        if (!ALLOW_STALE_CONSULTS) {
            require(lastUpdatedAt > block.timestamp - CONSULT_LENIENCY, "Oracle: Stale");
        }
        uint256 _normalizedPrice = uint256(price).mul(1e10);

        amountOut = uint144(_amountIn.mul(_normalizedPrice).div(1e21));
    }

    function twap(address _token, uint256 _amountIn) external view returns (uint144 _amountOut) {
        return consult(_token, _amountIn);
    }

    event Updated(uint256 price0CumulativeLast, uint256 price1CumulativeLast);
}

