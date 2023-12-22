// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0 <0.8.0;

import "./IUniswapV3PoolImmutables.sol";
import "./OracleLibrary.sol";
import "./TickMath.sol";
import "./FullMath.sol";
import "./Ownable.sol";
import "./IChainlinkAggregator.sol";


contract ZarPriceOracle is Ownable {
    uint256 public decimals;
    string public description;
    address public pool;
    address public zar;
    bool public zarIsToken0;
    uint32 public secondsAgo;
    uint256 public baseAmount;
    IChainlinkAggregator public daiUsdPriceFeed;
    uint8 public daiUsdDecimals;


    event SecondsAgoUpdated(uint32 secondsAgo);

    constructor(string memory _description, uint256 _decimals, address _pool, address _zar, uint32 _secondsAgo, address _daiUsdPriceFeed) {
        description = _description;
        decimals = _decimals;
        pool = _pool;
        zar = _zar;
        secondsAgo = _secondsAgo;
        baseAmount = 10 ** decimals;

        IUniswapV3PoolImmutables p = IUniswapV3PoolImmutables(_pool);
        zarIsToken0 = _zar == p.token0();

        daiUsdPriceFeed = IChainlinkAggregator(_daiUsdPriceFeed);
        daiUsdDecimals = daiUsdPriceFeed.decimals();
    }

    function getAssetPrice() public view returns (uint256) {
        (int24 tick,) = OracleLibrary.consult(pool, secondsAgo);

        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
        uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;

        uint256 quoteAmount;
        if (zarIsToken0) {
            quoteAmount = FullMath.mulDiv(ratioX192, baseAmount, 1 << (192));
        } else {
            quoteAmount; FullMath.mulDiv(ratioX192, 1 << (192), baseAmount);
        }

        // get DAI/USD price from chainlink price feed
        int256 daiPrice = daiUsdPriceFeed.latestAnswer();

        // calculate ZAR/USD price
        uint256 price = FullMath.mulDiv(quoteAmount, uint256(daiPrice), 10 ** uint256(daiUsdDecimals));
        return price;

    }

    function setSecondsAgo(uint32 _secondsAgo) external onlyOwner {
        secondsAgo = _secondsAgo;
        emit SecondsAgoUpdated(_secondsAgo);
    }

    function setChainlinkDaiUsdPriceFeed(address _daiUsdPriceFeed) external onlyOwner {
        daiUsdPriceFeed = IChainlinkAggregator(_daiUsdPriceFeed);
    }
}
