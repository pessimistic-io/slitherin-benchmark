// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {IOracle} from "./IOracle.sol";
import {ISushiSwapV2Pair} from "./ISushiSwapV2Pair.sol";
import {IERC20WithDeciamls} from "./IERC20WithDeciamls.sol";
import {SafeMath} from "./SafeMath.sol";
import {GmuMath} from "./GmuMath.sol";

contract ChainlinkUniswapLPOracle is AggregatorV3Interface {
    using SafeMath for uint256;
    using GmuMath for uint256;

    ISushiSwapV2Pair public lp;
    IERC20WithDeciamls public tokenA;
    IERC20WithDeciamls public tokenB;

    AggregatorV3Interface public tokenAoracle;
    AggregatorV3Interface public tokenBoracle;

    uint256 public constant maxDelayTime = 86400;
    uint256 public constant TARGET_DIGITS = 8;

    constructor(address _tokenAoracle, address _tokenBoracle, address _lp) {
        lp = ISushiSwapV2Pair(_lp);
        tokenAoracle = AggregatorV3Interface(_tokenAoracle);
        tokenBoracle = AggregatorV3Interface(_tokenBoracle);

        tokenA = IERC20WithDeciamls(lp.token0());
        tokenB = IERC20WithDeciamls(lp.token1());
    }

    function fetchPrice() external view returns (uint256) {
        return _fetchPrice();
    }

    function tokenAPrice() public view returns (uint256) {
        return _getCurrentChainlinkResponse(tokenA, tokenAoracle);
    }

    function tokenBPrice() public view returns (uint256) {
        return _getCurrentChainlinkResponse(tokenB, tokenBoracle);
    }

    // this code is a port of AlphaHomora's fair LP oracle
    // https://github.com/AlphaFinanceLab/alpha-homora-v2-contract/blob/master/contracts/oracle/UniswapV2Oracle.sol
    function _fetchPrice() internal view returns (uint) {
        uint256 totalSupply = lp.totalSupply();
        (uint256 r0, uint256 r1) = lp.getReserves();
        uint256 sqrtK = GmuMath.sqrt(r0.mul(r1)).fdiv(totalSupply); // in 2**112

        uint256 px0 = _getCurrentChainlinkResponse(tokenA, tokenAoracle); // in 2**112
        uint256 px1 = _getCurrentChainlinkResponse(tokenB, tokenBoracle); // in 2**112

        // fair token0 amt: sqrtK * sqrt(px1/px0)
        // fair token1 amt: sqrtK * sqrt(px0/px1)
        // fair lp price = 2 * sqrt(px0 * px1)
        // split into 2 sqrts multiplication to prevent uint overflow (note the 2**112)
        uint256 answer = sqrtK
            .mul(2)
            .mul(GmuMath.sqrt(px0))
            .div(2 ** 56)
            .mul(GmuMath.sqrt(px1))
            .div(2 ** 56);

        return answer.mul(1e18).div(2 ** 112);
    }

    /// @dev Return token price, multiplied by 2**112
    /// @param token Token address to get price
    /// @param agg Chainlink aggreagtor to pass
    function _getCurrentChainlinkResponse(
        IERC20WithDeciamls token,
        AggregatorV3Interface agg
    ) internal view virtual returns (uint256) {
        uint256 _decimals = uint256(token.decimals());
        (, int answer, , uint256 updatedAt, ) = agg.latestRoundData();

        require(
            updatedAt >= block.timestamp.sub(maxDelayTime),
            "delayed update time"
        );

        return uint256(answer).mul(2 ** 112).div(10 ** _decimals);
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

