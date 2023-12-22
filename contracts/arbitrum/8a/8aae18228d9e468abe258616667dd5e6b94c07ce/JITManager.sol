// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

import {IERC20Metadata} from "./IERC20Metadata.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {TickMath} from "./TickMath.sol";
import {FullMath} from "./FullMath.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";

import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {PoolAddress} from "./PoolAddress.sol";

import {IJITManager} from "./IJITManager.sol";

import {console} from "./console.sol";

contract JITManager is IJITManager, Initializable, OwnableUpgradeable {
    uint constant BPS = 10000;
    address public uniswapV3Factory;
    INonfungiblePositionManager public nfpm;

    address public keeper;
    address public authorizedCaller;

    IERC20Metadata public token0; // token0
    IERC20Metadata public token1; // token1
    uint24 public feeTier;
    IUniswapV3Pool public pool;
    int24 public tickSpacing;

    AggregatorV3Interface public token0PriceFeed;
    AggregatorV3Interface public token1PriceFeed;

    uint public sqrtPriceThresholdBPS;
    uint public swapLossThresholdBPS;
    uint public priceDeviationThresholdBPS;

    uint128 public nfpmTokenId;
    uint128 public liquidity;

    modifier onlyKeeper() {
        require(msg.sender == keeper, "JITManager: not keeper");
        _;
    }

    modifier onlyAuthorizedCaller() {
        require(
            msg.sender == authorizedCaller,
            "JITManager: not authorizedCaller"
        );
        _;
    }

    function initialize(
        address _uniswapV3Factory,
        address _nfpm,
        address _token0,
        address _token1,
        uint24 _feeTier
    ) public initializer {
        __Ownable_init();
        uniswapV3Factory = _uniswapV3Factory;
        nfpm = INonfungiblePositionManager(_nfpm);
        token0 = IERC20Metadata(_token0);
        token1 = IERC20Metadata(_token1);
        feeTier = _feeTier;

        // this somehow gives wrong address
        // pool = IUniswapV3Pool(
        //     PoolAddress.computeAddress(
        //         uniswapV3Factory,
        //         PoolAddress.PoolKey(address(token0), address(token1), _feeTier)
        //     )
        // );

        pool = IUniswapV3Pool(
            IUniswapV3Factory(uniswapV3Factory).getPool(
                address(token0),
                address(token1),
                _feeTier
            )
        );

        tickSpacing = pool.tickSpacing();

        // grant allowances to NFPM
        token0.approve(address(nfpm), type(uint).max);
        token1.approve(address(nfpm), type(uint).max);
    }

    /// @notice Allows owner to set values
    function setValues(
        address _keeper,
        address _authorizedCaller,
        address _token0PriceFeed,
        address _token1PriceFeed,
        uint _sqrtPriceThresholdBPS,
        uint _swapLossThresholdBPS,
        uint _priceDeviationThresholdBPS
    ) external onlyOwner {
        keeper = _keeper;
        authorizedCaller = _authorizedCaller;
        token0PriceFeed = AggregatorV3Interface(_token0PriceFeed);
        token1PriceFeed = AggregatorV3Interface(_token1PriceFeed);
        sqrtPriceThresholdBPS = _sqrtPriceThresholdBPS;
        swapLossThresholdBPS = _swapLossThresholdBPS;
        priceDeviationThresholdBPS = _priceDeviationThresholdBPS;
    }

    /// @inheritdoc IJITManager
    function addLiquidity(bool isToken0) external onlyAuthorizedCaller {
        require(nfpmTokenId == 0, "JITManager: cannot add liquidity twice");

        (int24 tickLower, int24 tickUpper) = getTickRange(isToken0);

        uint tokenBalance = (isToken0 ? token0 : token1).balanceOf(
            address(this)
        );

        (uint _nfpmTokenId, uint128 _liquidity, , ) = nfpm.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: feeTier,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: (isToken0 ? tokenBalance : 0),
                amount1Desired: (isToken0 ? 0 : tokenBalance),
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );
        nfpmTokenId = uint128(_nfpmTokenId);
        liquidity = _liquidity;
    }

    /// @inheritdoc IJITManager
    function removeLiquidity() external onlyAuthorizedCaller {
        require(nfpmTokenId > 0, "JITManager: cannot remove");
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

    // TODO generalize this as well
    /// @inheritdoc IJITManager
    function swapTokens(
        address to,
        bytes calldata data,
        bool approveToken0
    ) external onlyKeeper {
        require(
            to != address(token0) || to != address(token1),
            "JITManager: cannot call token contract"
        );

        uint valueBefore = getDollarValue();

        IERC20Metadata token = approveToken0 ? token0 : token1;

        token.approve(to, type(uint).max);
        (bool success, bytes memory ret) = address(to).call(data);
        require(success, string(ret));
        token.approve(to, 0);

        uint valueAfter = getDollarValue();
        require(valueAfter * BPS >= valueBefore * (BPS - swapLossThresholdBPS));
    }

    function withdrawFunds(address token) external onlyOwner {
        uint bal = IERC20Metadata(token).balanceOf(address(this));
        IERC20Metadata(token).transfer(owner(), bal);
    }

    /// @notice Gives a smallest tick range off from the current price by the price threshold
    /// @param isToken0 Whether the token0 order is created (token0 is sold by this contract)
    /// @return tickLower The lower tick of the range
    /// @return tickUpper The upper tick of the range
    function getTickRange(
        bool isToken0
    ) public view returns (int24 tickLower, int24 tickUpper) {
        // check if price is not deviated too much from the oracle price
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        (uint deviationBPS, , ) = getDeviationFromChainlink(sqrtPriceX96);
        require(
            deviationBPS < priceDeviationThresholdBPS,
            "JITManager: price is deviated too much"
        );

        uint160 targetSqrtPriceX96 = isToken0
            ? uint160((sqrtPriceX96 * (BPS + sqrtPriceThresholdBPS)) / BPS) // selling token0 increases sqrtPrice
            : uint160((sqrtPriceX96 * (BPS - sqrtPriceThresholdBPS)) / BPS); // selling token1 decreases sqrtPrice

        int24 tickThreshold = TickMath.getTickAtSqrtRatio(targetSqrtPriceX96);
        if (isToken0) {
            // gives a rounded up tick range
            tickLower =
                tickThreshold -
                (tickThreshold % tickSpacing) +
                tickSpacing;
            tickUpper = tickLower + tickSpacing;
        } else {
            // gives a rounded down tick range
            tickUpper = tickThreshold - (tickThreshold % tickSpacing);
            tickLower = tickUpper - tickSpacing;
        }
    }

    function getDollarValue() public view returns (uint dollarValueD6) {
        uint256 token0PriceD8 = getPrice(token0PriceFeed);
        uint balance0 = token0.balanceOf(address(this));
        uint decimals0 = token0.decimals();
        dollarValueD6 += (token0PriceD8 * balance0) / (10 ** (2 + decimals0));

        uint256 token1PriceD8 = getPrice(token1PriceFeed);
        uint balance1 = token1.balanceOf(address(this));
        uint decimals1 = token1.decimals();
        dollarValueD6 += (token1PriceD8 * balance1) / (10 ** (2 + decimals1));
    }

    function getPrice(
        AggregatorV3Interface priceFeed
    ) public view returns (uint) {
        if (address(priceFeed) == address(0)) {
            return 1e8;
        }

        (, int256 tokenPriceD8, , , ) = priceFeed.latestRoundData();
        return uint(tokenPriceD8);
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
        uint usdPerToken0D8 = getPrice(token0PriceFeed);
        uint usdPerToken1D8 = getPrice(token1PriceFeed);

        uint decimals0 = token0.decimals();
        uint decimals1 = token1.decimals();

        // normalising prices to token1 per token0 in X128
        uniswapPriceX128 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 1 << 64);
        chainlinkPriceX128 = FullMath.mulDiv(
            usdPerToken0D8, // token0 stays in denominator
            decimals1 > decimals0
                ? (10 ** (decimals1 - decimals0)) << 128
                : (1 << 128) / (10 ** (decimals0 - decimals1)),
            usdPerToken1D8 // token1 climbs to numerator
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

