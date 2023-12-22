// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AggregatorV3Interface, ChainlinkUniswapLPOracle} from "./ChainlinkUniswapLPOracle.sol";
import {SafeMath} from "./SafeMath.sol";
import {PriceConsumerWithSequencerCheck} from "./PriceConsumerWithSequencerCheck.sol";
import {IERC20WithDeciamls} from "./IERC20WithDeciamls.sol";

contract ChainlinkUniswapLPOracleWithSequencer is
    ChainlinkUniswapLPOracle,
    PriceConsumerWithSequencerCheck
{
    using SafeMath for uint256;
    AggregatorV3Interface public sequencerUptimeFeed;

    constructor(
        address _sequencerUptimeFeed,
        address _tokenAoracle,
        address _tokenBoracle,
        address _lp
    ) ChainlinkUniswapLPOracle(_tokenAoracle, _tokenBoracle, _lp) {
        sequencerUptimeFeed = AggregatorV3Interface(_sequencerUptimeFeed);
    }

    /// @dev Return token price, multiplied by 2**112
    /// @param token Token address to get price
    /// @param agg Chainlink aggreagtor to pass
    function _getCurrentChainlinkResponse(
        IERC20WithDeciamls token,
        AggregatorV3Interface agg
    ) internal view override returns (uint256) {
        uint256 _decimals = uint256(token.decimals());
        (int answer, uint256 updatedAt) = getLatestPriceWithCheck(
            agg,
            sequencerUptimeFeed
        );

        require(
            updatedAt >= block.timestamp.sub(maxDelayTime),
            "delayed update time"
        );

        return uint256(answer).mul(2 ** 112).div(10 ** _decimals);
    }
}

