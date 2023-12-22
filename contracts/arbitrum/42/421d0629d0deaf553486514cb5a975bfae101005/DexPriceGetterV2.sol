// SPDX-License-Identifier: GPL-3.0-or-later

/*
 //======================================================================\\
 //======================================================================\\
    *******         **********     ***********     *****     ***********
    *      *        *              *                 *       *
    *        *      *              *                 *       *
    *         *     *              *                 *       *
    *         *     *              *                 *       *
    *         *     **********     *       *****     *       ***********
    *         *     *              *         *       *                 *
    *         *     *              *         *       *                 *
    *        *      *              *         *       *                 *
    *      *        *              *         *       *                 *
    *******         **********     ***********     *****     ***********
 \\======================================================================//
 \\======================================================================//
*/

pragma solidity ^0.8.13;

import "./IUniswapV3Pool.sol";
import "./TickMath.sol";
import "./FixedPoint96.sol";
import "./FullMath.sol";

import "./ILBPair.sol";
import "./ILBFactory.sol";
import "./IUniswapV3Factory.sol";
import "./IPriceGetter.sol";

import "./OwnableWithoutContextUpgradeable.sol";

import "./console.sol";

contract DexPriceGetterV2 is OwnableWithoutContextUpgradeable {
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address public constant JOE = 0x371c7ec6D8039ff7933a2AA28EB827Ffe1F52f07;
    address public constant ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;

    address public constant JOE_LB_FACTORY =
        0x8e42f2F4101563bF679975178e880FD87d3eFd4e;

    address public constant UNI_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address public constant WOM = 0x7B5EB3940021Ec0e8e463D5dBB4B7B09a89DDF96;

    uint256 public constant WOM_USDT_FEE = 3000;

    uint256 public constant GMX_WETH_FEE = 3000;
    uint256 public constant GNS_WETH_FEE = 3000;
    uint256 public constant LDO_WETH_FEE = 3000;
    uint256 public constant ARB_WETH_FEE = 500;

    // Base price getter to transfer the price into USD
    IPriceGetter public basePriceGetter;

    struct LBPriceFeedInfo {
        uint64 lastCumulativeId;
        uint256 lastTimestamp;
        uint256 price;
    }
    mapping(address => LBPriceFeedInfo) public lbPriceFeeds;

    function initialize(address _priceGetter) public initializer {
        __Ownable_init();

        basePriceGetter = IPriceGetter(_priceGetter);
    }

    function getLatestPrice(address _token) external returns (uint256) {
        if (_token == JOE) {
            if (block.timestamp - lbPriceFeeds[_token].lastTimestamp <= 3600)
                return lbPriceFeeds[_token].price;
            else return samplePriceFromLB(_token);
        } else return samplePriceFromUniV3(_token);
    }

    function getSqrtTwapX96(
        address uniswapV3Pool,
        uint32 twapInterval
    ) public view returns (uint160 sqrtPriceX96) {
        if (twapInterval == 0) {
            // return the current price if twapInterval == 0
            (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapV3Pool).slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapInterval; // from (before)
            secondsAgos[1] = 0; // to (now)

            (int56[] memory tickCumulatives, ) = IUniswapV3Pool(uniswapV3Pool)
                .observe(secondsAgos);

            // tick(imprecise as it's an integer) to price
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
                int24(
                    uint24(
                        uint32(
                            uint56((tickCumulatives[1] - tickCumulatives[0]))
                        ) / twapInterval
                    )
                )
            );
        }
    }

    function getPriceX96FromSqrtPriceX96(
        uint160 sqrtPriceX96
    ) public pure returns (uint256 priceX96) {
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }

    function samplePriceFromUniV3(address _token) public returns (uint256) {
        uint256 fee = _token == ARB ? ARB_WETH_FEE : 3000;

        address pool;

        if (_token == WOM) {
            pool = IUniswapV3Factory(UNI_V3_FACTORY).getPool(WOM, USDT, 3000);
        } else {
            pool = IUniswapV3Factory(UNI_V3_FACTORY).getPool(
                _token,
                WETH,
                uint24(fee)
            );
        }

        uint256 priceX96 = getPriceX96FromSqrtPriceX96(
            getSqrtTwapX96(pool, 3600)
        );

        uint256 ethPrice = basePriceGetter.getLatestPrice(WETH);
    }

    function samplePriceFromLB(address _token) public returns (uint256) {
        ILBFactory.LBPairInformation memory pairInfo = ILBFactory(
            JOE_LB_FACTORY
        ).getLBPairInformation(
                IERC20(_token),
                IERC20(WETH),
                _getLBPairBinStep(_token)
            );

        address pair = address(pairInfo.LBPair);

        (uint64 cumulativeId, , ) = ILBPair(pair).getOracleSampleAt(
            uint40(block.timestamp)
        );

        LBPriceFeedInfo storage lbPriceFeed = lbPriceFeeds[_token];

        if (lbPriceFeed.lastTimestamp == 0) {
            lbPriceFeed.lastTimestamp = block.timestamp;
            lbPriceFeed.lastCumulativeId = cumulativeId;
            return 0;
        }

        uint256 timeElapsed = block.timestamp - lbPriceFeed.lastTimestamp;

        console.log("timeElapsed: %s", timeElapsed);
        console.log("cumulativeId: %s", cumulativeId);
        console.log("lastCumulativeId: %s", lbPriceFeed.lastCumulativeId);

        uint256 averageId = uint256(
            cumulativeId - lbPriceFeed.lastCumulativeId
        ) / timeElapsed;

        console.log("averageId: %s", averageId);

        uint256 price = ILBPair(pair).getPriceFromId(uint24(averageId));

        console.log("price: %s", price);

        lbPriceFeed.price = (price * 1e18) / 2 ** 128;
        lbPriceFeed.lastCumulativeId = cumulativeId;
        lbPriceFeed.lastTimestamp = block.timestamp;

        uint256 ethPrice = basePriceGetter.getLatestPrice(WETH);
        uint256 finalPrice = (ethPrice * price) / 1e18;

        return finalPrice;
    }

    function _getLBPairBinStep(
        address _token
    ) internal pure returns (uint256 binStep) {
        if (_token == JOE) {
            binStep = 20;
        } else revert("Wrong token");
    }
}

