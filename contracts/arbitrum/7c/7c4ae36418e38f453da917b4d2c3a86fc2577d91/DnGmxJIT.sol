// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

import {IERC20Minimal} from "./IERC20Minimal.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {TickMath} from "./TickMath.sol";
import {FullMath} from "./FullMath.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";

import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {PoolAddress} from "./PoolAddress.sol";

import {IDnGmxJIT} from "./IDnGmxJIT.sol";

import {console} from "./console.sol";

contract DnGmxJIT is IDnGmxJIT, Initializable, OwnableUpgradeable {
    uint constant BPS = 10000;
    address public uniswapV3Factory;
    INonfungiblePositionManager public nfpm;

    address public keeper;
    address public dnGmxRouter;

    IERC20Minimal public weth;
    IERC20Minimal public wbtc;
    uint24 public feeTier;
    IUniswapV3Pool public pool;
    int24 public tickSpacing;

    AggregatorV3Interface public chainlinkEthFeed;
    AggregatorV3Interface public chainlinkBtcFeed;

    uint public sqrtPriceThresholdBPS;
    uint public swapLossThresholdBPS;
    uint public priceDeviationThresholdBPS;

    uint128 public nfpmTokenId;
    uint128 public liquidity;

    modifier onlyKeeper() {
        require(msg.sender == keeper, "DnGmxJIT: not keeper");
        _;
    }

    modifier onlyDnGmxRouter() {
        require(msg.sender == dnGmxRouter, "DnGmxJIT: not dnGmxRouter");
        _;
    }

    function initialize(
        address _uniswapV3Factory,
        address _nfpm,
        address _weth,
        address _wbtc
    ) public initializer {
        __Ownable_init();
        uniswapV3Factory = _uniswapV3Factory;
        nfpm = INonfungiblePositionManager(_nfpm);
        weth = IERC20Minimal(_weth);
        wbtc = IERC20Minimal(_wbtc);
    }

    /// @notice Allows owner to set values
    function setValues(
        address _keeper,
        address _dnGmxRouter,
        uint24 _feeTier,
        address _chainlinkEthFeed,
        address _chainlinkBtcFeed,
        uint _sqrtPriceThresholdBPS,
        uint _swapLossThresholdBPS,
        uint _priceDeviationThresholdBPS
    ) external onlyOwner {
        keeper = _keeper;
        dnGmxRouter = _dnGmxRouter;
        feeTier = _feeTier;
        chainlinkEthFeed = AggregatorV3Interface(_chainlinkEthFeed);
        chainlinkBtcFeed = AggregatorV3Interface(_chainlinkBtcFeed);
        sqrtPriceThresholdBPS = _sqrtPriceThresholdBPS;
        swapLossThresholdBPS = _swapLossThresholdBPS;
        priceDeviationThresholdBPS = _priceDeviationThresholdBPS;

        // this somehow gives wrong address
        // pool = IUniswapV3Pool(
        //     PoolAddress.computeAddress(
        //         uniswapV3Factory,
        //         PoolAddress.PoolKey(address(wbtc), address(weth), _feeTier)
        //     )
        // );

        pool = IUniswapV3Pool(
            IUniswapV3Factory(uniswapV3Factory).getPool(
                address(wbtc),
                address(weth),
                _feeTier
            )
        );

        tickSpacing = pool.tickSpacing();

        // grant allowances to NFPM
        weth.approve(address(nfpm), type(uint).max);
    }

    /// @inheritdoc IDnGmxJIT
    function addLiquidity() external onlyDnGmxRouter {
        require(nfpmTokenId == 0, "DnGmxJIT: cannot add liquidity twice");

        (int24 tickLower, int24 tickUpper) = getTickRange();

        uint wethBalance = weth.balanceOf(address(this));

        (uint _nfpmTokenId, uint128 _liquidity, , ) = nfpm.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(wbtc),
                token1: address(weth),
                fee: pool.fee(),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: 0,
                amount1Desired: wethBalance,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );
        nfpmTokenId = uint128(_nfpmTokenId);
        liquidity = _liquidity;
    }

    /// @inheritdoc IDnGmxJIT
    function removeLiquidity() external onlyDnGmxRouter {
        require(nfpmTokenId > 0, "DnGmxJIT: cannot remove");
        nfpm.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: nfpmTokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );
        nfpm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: nfpmTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        nfpm.burn(nfpmTokenId);
        nfpmTokenId = 0;
    }

    /// @inheritdoc IDnGmxJIT
    function swapWbtc(address to, bytes calldata data) external onlyKeeper {
        require(
            to != address(weth) || to != address(wbtc),
            "DnGmxJIT: cannot call token contract"
        );

        uint valueBefore = getDollarValue();

        wbtc.approve(to, type(uint).max);
        (bool success, bytes memory ret) = address(to).call(data);
        require(success, string(ret));
        wbtc.approve(to, 0);

        uint valueAfter = getDollarValue();
        require(valueAfter * BPS >= valueBefore * (BPS - swapLossThresholdBPS));
    }

    function withdrawFunds(address token) external onlyOwner {
        uint bal = IERC20Minimal(token).balanceOf(address(this));
        IERC20Minimal(token).transfer(owner(), bal);
    }

    /// @notice Gives a smallest tick range off from the current price by the price threshold
    function getTickRange()
        public
        view
        returns (int24 tickLower, int24 tickUpper)
    {
        // TODO do a sanity check if price is not deviated too much from the oracle price
        (uint160 sqrtPriceX96, int24 tickCurrent, , , , , ) = pool.slot0();
        (uint deviationBPS, , ) = getDeviationFromChainlink(sqrtPriceX96);
        require(
            deviationBPS < priceDeviationThresholdBPS,
            "DnGmxJIT: price is deviated too much"
        );

        // gives a rounded down tick
        int24 tickThreshold = TickMath.getTickAtSqrtRatio(
            // selling wbtc for weth, reduces sqrtPrice
            uint160((sqrtPriceX96 * (BPS - sqrtPriceThresholdBPS)) / BPS)
        );
        tickUpper = tickThreshold - (tickThreshold % tickSpacing);

        // >= is to avoid a case where price is between tickLower and tickUpper (needing to hold WBTC)
        if (tickUpper >= tickCurrent) {
            tickUpper -= tickSpacing;
        }
        tickLower = tickUpper - tickSpacing;
    }

    function getDollarValue() public view returns (uint dollarValueD6) {
        (, int256 ethPriceD8, , , ) = chainlinkEthFeed.latestRoundData();
        uint balanceD18 = weth.balanceOf(address(this));
        dollarValueD6 += (uint(ethPriceD8) * balanceD18) / 1e20;

        (, int256 btcPriceD8, , , ) = chainlinkBtcFeed.latestRoundData();
        uint balanceD8 = wbtc.balanceOf(address(this));
        dollarValueD6 += (uint(btcPriceD8) * balanceD8) / 1e10;
    }

    function getDeviationFromChainlink(
        uint160 sqrtPrice
    )
        public
        view
        returns (
            uint deviationBPS,
            uint uniswapPriceX128,
            uint chainlinkPriceX128
        )
    {
        uint usdPerEthD8;
        uint usdPerBtcD8;
        {
            (, int256 _usdPerEthD8, , , ) = chainlinkEthFeed.latestRoundData();
            (, int256 _usdPerBtcD8, , , ) = chainlinkBtcFeed.latestRoundData();
            usdPerEthD8 = uint(_usdPerEthD8);
            usdPerBtcD8 = uint(_usdPerBtcD8);
        }

        // normalising prices to ETH per BTC in X128
        uniswapPriceX128 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 1 << 64);
        chainlinkPriceX128 = FullMath.mulDiv(
            usdPerBtcD8,
            (1e10) << 128, // 18 - 8
            usdPerEthD8
        );

        // abs(uniswap price - chainlink price) / chainlink price
        deviationBPS = FullMath.mulDiv(
            (
                uniswapPriceX128 > chainlinkPriceX128
                    ? uniswapPriceX128 - chainlinkPriceX128
                    : chainlinkPriceX128 - uniswapPriceX128
            ),
            BPS,
            chainlinkPriceX128
        );
    }
}

