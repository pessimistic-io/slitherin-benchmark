/**
 * Adapter for chainlink's pricefeeds
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {IDataProvider} from "./IDataProvider.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {IERC20} from "./IERC20.sol";
import {Ownable} from "./Ownable.sol";
import "./console.sol";

contract ChainlinkAdapter is IDataProvider, Ownable {
    // ==================
    //      ERRORS
    // ==================
    error NoPricefeedForToken();

    // ==================
    //      STORAGE
    // ==================
    /**
     * SOL/USD AggregatorV3 price feed
     */
    AggregatorV3Interface SOL_USD_PRICEFEED;

    /**
     * ETH/USD AggregatorV3 price feed
     */
    AggregatorV3Interface ETH_USD_PRICEFEED;

    /**
     * Map token addresses => corresponding AggregatorV3Interfaces against USD
     */
    mapping(address token => AggregatorV3Interface priceFeed)
        public priceFeedsUSD;

    // ====================
    //      CONSTRUCTOR
    // ====================
    constructor(
        AggregatorV3Interface solUsdPricefeed,
        AggregatorV3Interface ethUsdPricefeed
    ) Ownable() {
        SOL_USD_PRICEFEED = solUsdPricefeed;
        ETH_USD_PRICEFEED = ethUsdPricefeed;
    }

    // ====================
    //      SETTERS
    // ====================
    function setTokenPriceFeed(
        address token,
        AggregatorV3Interface priceFeedAgainstUSD
    ) external onlyOwner {
        priceFeedsUSD[token] = priceFeedAgainstUSD;
    }

    // ====================
    //      LOGIC
    // ====================

    /**
     * Quote SOL To ETH
     * @param solAmount - SOL Amount to quote (With decimals ofc)
     * @return ethAmount - Eth amount to get against that SOL
     */
    function quoteSOLToETH(
        uint256 solAmount
    ) external view returns (uint256 ethAmount) {
        if (solAmount == 0) return 0;
        // Get SOL/USD price from the SOL price feed
        AggregatorV3Interface solPriceFeed = SOL_USD_PRICEFEED;
        (, int256 solPrice, , , ) = solPriceFeed.latestRoundData();
        uint256 solToUsdPrice = uint256(solPrice);

        // Get TOKEN/USD price from the TOKEN price feed
        AggregatorV3Interface tokenPriceFeed = ETH_USD_PRICEFEED;
        (, int256 tokenPrice, , , ) = tokenPriceFeed.latestRoundData();
        uint256 tokenToUsdPrice = uint256(tokenPrice);

        // Get the decimal places of the token
        uint256 tokenDecimals = 18;

        // Calculate the amount of tokens needed to match the SOL amount
        ethAmount = _quote(
            tokenToUsdPrice,
            solAmount,
            solToUsdPrice,
            tokenDecimals,
            18
        );
    }

    /**
     * Quote SOL To Token
     * @param pairToken - The token to quote against
     * @param solAmount - Amount of SOL to quote
     * @return tokenAmount - Token amount to get against that SOL
     */
    function quoteSOLToToken(
        address pairToken,
        uint256 solAmount
    ) external view returns (uint256 tokenAmount) {
        if (solAmount == 0) return 0;

        // Get TOKEN/USD price from the TOKEN price feed
        AggregatorV3Interface tokenPriceFeed = priceFeedsUSD[pairToken];

        if (address(tokenPriceFeed) == address(0)) revert NoPricefeedForToken();

        // Get SOL/USD price from the SOL price feed
        AggregatorV3Interface solPriceFeed = SOL_USD_PRICEFEED;
        (, int256 solPrice, , , ) = solPriceFeed.latestRoundData();
        uint256 solToUsdPrice = uint256(solPrice);

        (, int256 tokenPrice, , , ) = tokenPriceFeed.latestRoundData();
        uint256 tokenToUsdPrice = uint256(tokenPrice);

        // Get the decimal places of the token
        uint256 tokenDecimals = IERC20(pairToken).decimals();

        tokenAmount = _quote(
            tokenToUsdPrice,
            solAmount,
            solToUsdPrice,
            tokenDecimals,
            18
        );
    }

    function quoteETHToToken(
        address pairToken,
        uint256 ethAmount
    ) external view returns (uint256 tokenAmount) {
        if (ethAmount == 0) return 0;

        AggregatorV3Interface tokenPriceFeed = priceFeedsUSD[pairToken];

        if (address(tokenPriceFeed) == address(0)) revert NoPricefeedForToken();

        (, int256 ethToUsdQuote, , , ) = ETH_USD_PRICEFEED.latestRoundData();

        (, int256 tokenToUsdQuote, , , ) = tokenPriceFeed.latestRoundData();

        tokenAmount = _quote(
            uint256(tokenToUsdQuote),
            ethAmount,
            uint256(ethToUsdQuote),
            IERC20(pairToken).decimals(),
            18
        );
    }

    /**
     * Internal function to quote
     * @param destUsdQuote - Quote of USD per 1 destination token
     * @param srcAmount - The amount to quote in of the source token
     * @param srcToUsdQuote - QUote of USD per 1 source token
     * @param destDecimals - Decimals of the end token
     */
    function _quote(
        uint256 destUsdQuote,
        uint256 srcAmount,
        uint256 srcToUsdQuote,
        uint256 destDecimals,
        uint256 sourceDecimals
    ) internal pure returns (uint256 destAmount) {
        destAmount =
            ((srcAmount * srcToUsdQuote * (10 ** (destDecimals))) /
                destUsdQuote) /
            (10 ** sourceDecimals);
    }
}

