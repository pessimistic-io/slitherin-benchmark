// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

import {Byte3IncOnChainServices} from "./Byte3IncOnChainServices.sol";

import {ERC20} from "./ERC20.sol";
import {HolographerInterface} from "./HolographerInterface.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {IUniswapV3Pair} from "./IUniswapV3Pair.sol";
import {IWETH} from "./IWETH.sol";

contract Byte3IncOnChainServicesArbitrumOne is Byte3IncOnChainServices {
  uint256 internal constant Q96 = 0x1000000000000000000000000; // Uniswap V3 FixedPoint96

  address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // 18 decimals
  address constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // 6 decimals

  uint256 constant serviceFee = 100000; // $0.10 Byte3 service fee / per transaction

  IUniswapV2Pair constant SushiSwapV2UsdcPool = IUniswapV2Pair(0x905dfCD5649217c42684f23958568e533C711Aa3);
  IUniswapV3Pair constant UniswapV3UsdcPool = IUniswapV3Pair(0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443);

  uint256 internal _expectingCallback;
  uint256 internal _updatedBalance;

  constructor() {}

  function init(bytes memory data) external override returns (bytes4) {
    return _init(data);
  }

  function approve() external override onlyAdmin {
    // approve SushiSwap for WETH
    ERC20(WETH).approve(address(SushiSwapV2UsdcPool), type(uint256).max);
    // approve FractionToken for USDC
    ERC20(USDC).approve(address(_fractionToken()), type(uint256).max);
    // approve FractionToken SourceContract for USDC
    ERC20(USDC).approve(HolographerInterface(address(_fractionToken())).getSourceContract(), type(uint256).max);
  }

  function convertUsdToWei(uint256 usdAmount) external view override returns (uint256 weiAmount) {
    usdAmount += serviceFee;
    (uint256 uniswapWeiAmount,) = _getUniswapUSDC(usdAmount);
    weiAmount = (_getSushiSwapUSDC(usdAmount) + uniswapWeiAmount) / 2;
    // add 1% overhead
    weiAmount += weiAmount / 100;
  }

  function getUSDC() external pure override returns (address) {
    return USDC;
  }

  function getWETH() external pure override returns (address) {
    return WETH;
  }

  function needsApproval() external view override returns (bool) {
    if (
      ERC20(WETH).allowance(address(this), address(SushiSwapV2UsdcPool)) == 0 ||
      ERC20(USDC).allowance(address(this), address(_fractionToken())) == 0 ||
      ERC20(USDC).allowance(address(this), HolographerInterface(address(_fractionToken())).getSourceContract()) == 0
    ) {
      return true;
    }
    return false;
  }

  function purchaseFractionToken(
    address recipient,
    uint256 usdAmount
  ) external payable override returns (uint256 remainder) {
    usdAmount += serviceFee;
    // get amount sent
    uint256 value = msg.value;
    // buy USDC with WETH
    (uint256 _amountIn1, uint160 _amountIn1sqrtPrice) = _getUniswapUSDC(usdAmount);
    uint256 _amountIn2 = _getSushiSwapUSDC(usdAmount);
    uint256 amountIn = _amountIn1 < _amountIn2 ? _amountIn1 : _amountIn2;
    require(value >= amountIn, "BYTE3: insufficient msg.value");
    if (amountIn == _amountIn1) {
      amountIn = _uniswapSwap(address(this), amountIn, usdAmount, _amountIn1sqrtPrice);
    } else {
      _sushiswapSwap(address(this), amountIn, usdAmount);
    }
    // mint FRACT10N for USDC
    uint256 fractionAmount = (usdAmount - serviceFee) * (10 ** (18 - 6));
    _fractionToken().mint(recipient, fractionAmount);
    // get remainder
    remainder = value - amountIn;
    if (remainder > 0) {
      payable(msg.sender).transfer(remainder);
    }
    return remainder;
  }

  function _sushiswapSwap(address recipient, uint256 nativeAmount, uint256 usdAmount) internal {
    IWETH weth = IWETH(WETH);
    // wrap the native gas token
    weth.deposit{value: nativeAmount}();
    // transfer to token pool
    weth.transfer(address(SushiSwapV2UsdcPool), nativeAmount);
    // execute swap
    SushiSwapV2UsdcPool.swap(0, usdAmount, recipient, "");
  }

  function _uniswapSwap(address recipient, uint256 nativeAmount, uint256 usdAmount, uint160 sqrtPrice) internal returns(uint256) {
    _expectingCallback = 1;
    /// amount0 The delta of the balance of token0 of the pool, exact when negative, minimum when positive
    /// amount1 The delta of the balance of token1 of the pool, exact when negative, minimum when positive
    UniswapV3UsdcPool.swap(
      // recipient The address to receive the output of the swap
      recipient,
      // zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
      true,
      // amountSpecified The amount of the swap, which implicitly configures the swap as exact input (positive), or exact output (negative)
      -int256(usdAmount),
      // sqrtPriceLimitX96 The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this value after the swap. If one for zero, the price cannot be greater than this value after the swap
      ((sqrtPrice / (10**21)) - 1) * (10**21),
//       sqrtPrice - 1,
      // data Any data to be passed through to the callback
      abi.encode(nativeAmount)
    );
    return _updatedBalance;
  }

  function uniswapV3SwapCallback(int256 amount0Delta, int256, bytes calldata data) external {
    require(msg.sender == address(UniswapV3UsdcPool), "BYTE3: UniswapV3Pair call only");
    require(_expectingCallback == 1, "BYTE3: unexpected callback");
    _expectingCallback = 0;
    uint256 nativeAmount = abi.decode(data, (uint256));
    uint256 amountIn = uint256(amount0Delta);
    require(amountIn <= nativeAmount, "BYTE3: greedy pig");
    IWETH weth = IWETH(WETH);
    // wrap the native gas token
    weth.deposit{value: amountIn}();
    // transfer to token pool
    weth.transfer(address(UniswapV3UsdcPool), amountIn);
    _updatedBalance = amountIn;
  }

  function _getSushiSwapUSDC(uint256 usdAmount) internal view returns (uint256 weiAmount) {
    // add decimal places for amount IF decimals are above 6!
    //usdAmount = usdAmount * (10**(18 - 6));
    (uint112 _reserve0, uint112 _reserve1, ) = SushiSwapV2UsdcPool.getReserves();
    // x is always native token / WETH
    uint256 x = uint256(_reserve0);
    // y is always USD token / USDC
    uint256 y = uint256(_reserve1);

    uint256 numerator = (x * usdAmount) * 1000;
    uint256 denominator = (y - usdAmount) * 997;

    weiAmount = (numerator / denominator) + 1;
  }

  function _getUniswapUSDC(uint256 usdAmount) internal view returns (uint256 weiAmount, uint160 sqrtPrice) {
    // token0 == WETH
    // token1 == USDC
    (uint160 sqrtPriceX96, , , , , , ) = UniswapV3UsdcPool.slot0();
    sqrtPrice = sqrtPriceX96;
    uint128 liquidity = UniswapV3UsdcPool.liquidity();
    uint256 amount0 = (liquidity * Q96) / sqrtPrice;
    uint256 amount1 = (liquidity * sqrtPrice) / Q96;
    uint256 price = amount0 / amount1;
    weiAmount = price * usdAmount;
  }
}

