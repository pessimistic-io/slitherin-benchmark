// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {IOracle} from "./IOracle.sol";
import {ISushiSwapV2Pair} from "./ISushiSwapV2Pair.sol";
import {IERC20} from "./IERC20.sol";
import {SafeMath} from "./SafeMath.sol";

interface IERC20WithDeciamls is IERC20 {
    function decimals() external view returns (uint256);
}

contract ChainlinkLPOracle is AggregatorV3Interface {
    using SafeMath for uint256;

    ISushiSwapV2Pair public lp;
    IERC20WithDeciamls public tokenA;
    IERC20WithDeciamls public tokenB;

    AggregatorV3Interface public tokenAoracle;
    AggregatorV3Interface public tokenBoracle;

    uint256 public constant TARGET_DIGITS = 8;

    struct ChainlinkResponse {
        uint80 roundId;
        int256 answer;
        uint256 timestamp;
        bool success;
        uint8 decimals;
    }

    constructor(address _tokenAoracle, address _tokenBoracle, address _lp) {
        lp = ISushiSwapV2Pair(_lp);
        tokenAoracle = AggregatorV3Interface(_tokenAoracle);
        tokenBoracle = AggregatorV3Interface(_tokenBoracle);

        tokenA = IERC20WithDeciamls(lp.token0());
        tokenB = IERC20WithDeciamls(lp.token1());
    }

    function priceFor(uint256 amount) external view returns (uint256) {
        return amount.mul(_fetchPrice()).div(1e18);
    }

    function fetchPrice() external view returns (uint256) {
        return _fetchPrice();
    }

    function _fetchPrice() internal view returns (uint256) {
        uint256 totalSupply = lp.totalSupply();
        return totalInLP().mul(1e18).div(totalSupply);
    }

    function totalInLP() public view returns (uint256) {
        uint256 totalTokenAGMU = tokenAInLP();
        uint256 totalTokenBGMU = tokenBInLP();
        return totalTokenAGMU.add(totalTokenBGMU);
    }

    function tokenAInLP() public view returns (uint256) {
        uint256 price = tokenAPrice();
        (uint256 reserve0 /* uint256 reserve1 */ /* uint256 timestamp */, ) = lp
            .getReserves();
        uint256 bal = _scalePriceByDigits(reserve0, tokenA.decimals());
        return price.mul(bal).div(1e18);
    }

    function tokenBInLP() public view returns (uint256) {
        uint256 price = tokenBPrice();
        (
            ,
            /* uint256 reserve0 */
            uint256 reserve1 /* uint256 timestamp */
        ) = lp.getReserves();
        uint256 bal = _scalePriceByDigits(reserve1, tokenB.decimals());
        return price.mul(bal).div(1e18);
    }

    function tokenAPrice() public view returns (uint256) {
        return _fetchWithChainlink(tokenAoracle);
    }

    function tokenBPrice() public view returns (uint256) {
        return _fetchWithChainlink(tokenBoracle);
    }

    function _fetchWithChainlink(
        AggregatorV3Interface agg
    ) internal view returns (uint256) {
        uint256 chainlinkPrice = _fetchChainlinkPrice(agg);
        return chainlinkPrice;
    }

    function _scalePriceByDigits(
        uint256 _price,
        uint256 _answerDigits
    ) internal pure returns (uint256) {
        // Convert the price returned by the oracle to an 18-digit decimal for use.
        uint256 price;
        if (_answerDigits >= TARGET_DIGITS) {
            // Scale the returned price value down to Liquity's target precision
            price = _price.div(10 ** (_answerDigits - TARGET_DIGITS));
        } else if (_answerDigits < TARGET_DIGITS) {
            // Scale the returned price value up to Liquity's target precision
            price = _price.mul(10 ** (TARGET_DIGITS - _answerDigits));
        }
        return price;
    }

    function _fetchChainlinkPrice(
        AggregatorV3Interface agg
    ) internal view returns (uint256) {
        ChainlinkResponse
            memory chainlinkResponse = _getCurrentChainlinkResponse(agg);
        uint256 scaledChainlinkPrice = _scalePriceByDigits(
            uint256(chainlinkResponse.answer),
            chainlinkResponse.decimals
        );
        return scaledChainlinkPrice;
    }

    function _getCurrentChainlinkResponse(
        AggregatorV3Interface agg
    ) internal view returns (ChainlinkResponse memory chainlinkResponse) {
        // First, try to get current decimal precision:
        try agg.decimals() returns (uint8 _decimals) {
            // If call to Chainlink succeeds, record the current decimal precision
            chainlinkResponse.decimals = _decimals;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }

        // Secondly, try to get latest price data:
        try agg.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 /* startedAt */,
            uint256 timestamp,
            uint80 /* answeredInRound */
        ) {
            // If call to Chainlink succeeds, return the response and success = true
            chainlinkResponse.roundId = roundId;
            chainlinkResponse.answer = answer;
            chainlinkResponse.timestamp = timestamp;
            chainlinkResponse.success = true;
            return chainlinkResponse;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }
    }

    function decimals() external pure override returns (uint8) {
        return uint8(TARGET_DIGITS);
    }

    function description() external pure override returns (string memory) {
        return "A chainlink v3 aggregator for Uniswap v2 LP tokens.";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, int256(_fetchPrice()), 0, block.timestamp, _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, int256(_fetchPrice()), 0, block.timestamp, 1);
    }

    function latestAnswer() external view override returns (int256) {
        return int256(_fetchPrice());
    }

    function latestTimestamp() external view override returns (uint256) {
        return block.timestamp;
    }

    function latestRound() external view override returns (uint256) {
        return block.timestamp;
    }

    function getAnswer(uint256) external view override returns (int256) {
        return int256(_fetchPrice());
    }

    function getTimestamp(uint256) external view override returns (uint256) {
        return block.timestamp;
    }
}

