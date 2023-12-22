// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;

import "./ISwapPair.sol";
import "./ISwapFactory.sol";
import "./IWETH.sol";
import "./IUniswapV2Pair.sol";
import "./IERC20.sol";

// Add stable pools

interface IUniswapV2Factory {
  function pairCodeHash() external pure returns (bytes32);
}

interface ISwapRouter {
  function pairFor(
    address tokenA,
    address tokenB,
    bool stable
  ) external view returns (address pair);

  function addLiquidity(
    address tokenA,
    address tokenB,
    bool stable,
    uint256 amountA,
    uint256 amountB,
    uint256 amountMinA,
    uint256 amountMinB,
    address to,
    uint256 deadline
  )
    external
    returns (
      uint256 a,
      uint256 b,
      uint256 l
    );

  function getReserves(
    address tokenA,
    address tokenB,
    bool stable
  ) external view returns (uint256 reserveA, uint256 reserveB);

  function quoteLiquidity(
    uint256 amountA,
    uint256 reserveA,
    uint256 reserveB
  ) external pure returns (uint256 amountB);

  function sortTokens(address tokenA, address tokenB) external pure returns (address token0, address token1);
}

interface IZap {
  function zapIn(
    address _token,
    uint256 _amount,
    address _pool,
    uint256 _minPoolTokens,
    bytes memory _swapData,
    address to
  ) external payable returns (uint256 poolTokens);
}

contract Migrate {
  //using SafeMath for uint256;

  address public immutable router;
  address public immutable zap;
  address public immutable factory;
  address public immutable sushiFactory;

  constructor(
    address _sushiFactory,
    address _router,
    address _zap,
    address _factory
  ) {
    router = _router;
    zap = _zap;
    factory = _factory;
    sushiFactory = _sushiFactory;
  }

  function migratePair(
    address tokenA,
    address tokenB,
    bool stable,
    uint256 liquidityOut,
    uint256 minPoolTokens,
    uint256 deadline,
    address to
  ) public returns (uint256 finalPoolTokens) {
    address pair = ISwapRouter(router).pairFor(tokenA, tokenB, stable);
    (uint256 amountA, uint256 amountB) = removeLiquidity(tokenA, tokenB, liquidityOut, 0, 0);

    (uint256 pooledAmountA, uint256 pooledAmountB, uint256 liquidity) = addLiquidity(
      tokenA,
      tokenB,
      stable,
      amountA,
      amountB,
      to,
      deadline
    );

    finalPoolTokens += liquidity;

    if (amountA > pooledAmountA) {
      IERC20(tokenA).approve(zap, amountA - pooledAmountA);
      finalPoolTokens += IZap(zap).zapIn(tokenA, amountA - pooledAmountA, pair, 0, new bytes(0), to);
    }

    if (amountB > pooledAmountB) {
      IERC20(tokenB).approve(zap, amountB - pooledAmountB);
      finalPoolTokens += IZap(zap).zapIn(tokenB, amountB - pooledAmountB, pair, 0, new bytes(0), to);
    }

    require(finalPoolTokens >= minPoolTokens, "Insufficient LP migrated");

    return finalPoolTokens;
  }

  // calculates the CREATE2 address for a pair without making any external calls
  function pairForOldRouter(address tokenA, address tokenB) internal view returns (address pair) {
    (address token0, address token1) = ISwapRouter(router).sortTokens(tokenA, tokenB);
    pair = address(
      uint160(
        uint256(
          keccak256(
            abi.encodePacked(
              hex"ff",
              sushiFactory,
              keccak256(abi.encodePacked(token0, token1)),
              IUniswapV2Factory(sushiFactory).pairCodeHash() // init code hash
            )
          )
        )
      )
    );
  }

  function removeLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin
  ) internal returns (uint256 amountA, uint256 amountB) {
    IUniswapV2Pair pair = IUniswapV2Pair(pairForOldRouter(tokenA, tokenB));
    pair.transferFrom(msg.sender, address(pair), liquidity);
    (uint256 amount0, uint256 amount1) = pair.burn(address(this));
    (address token0, ) = ISwapRouter(router).sortTokens(tokenA, tokenB);
    (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
    require(amountA >= amountAMin, "Xcalibur: INSUFFICIENT_A_AMOUNT");
    require(amountB >= amountBMin, "Xcalibur: INSUFFICIENT_B_AMOUNT");
  }

  function addLiquidity(
    address tokenA,
    address tokenB,
    bool stable,
    uint256 amountADesired,
    uint256 amountBDesired,
    address to,
    uint256 deadline
  )
    internal
    returns (
      uint256 amountA,
      uint256 amountB,
      uint256 liquidity
    )
  {
    require(deadline >= block.timestamp, "BaseV1Router: EXPIRED");
    (amountA, amountB) = _addLiquidity(tokenA, tokenB, stable, amountADesired, amountBDesired);
    address pair = ISwapRouter(router).pairFor(tokenA, tokenB, stable);
    IERC20(tokenA).transfer(pair, amountA);
    IERC20(tokenB).transfer(pair, amountB);
    liquidity = IUniswapV2Pair(pair).mint(to);
  }

  function _addLiquidity(
    address tokenA,
    address tokenB,
    bool stable,
    uint256 amountADesired,
    uint256 amountBDesired
  ) internal returns (uint256 amountA, uint256 amountB) {
    // create the pair if it doesn't exist yet
    address _pair = ISwapFactory(factory).getPair(tokenA, tokenB, stable);
    if (_pair == address(0)) {
      _pair = ISwapFactory(factory).createPair(tokenA, tokenB, stable);
    }
    (uint256 reserveA, uint256 reserveB) = ISwapRouter(router).getReserves(tokenA, tokenB, stable);
    if (reserveA == 0 && reserveB == 0) {
      (amountA, amountB) = (amountADesired, amountBDesired);
    } else {
      uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;
      if (amountBOptimal <= amountBDesired) {
        (amountA, amountB) = (amountADesired, amountBOptimal);
      } else {
        uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;
        assert(amountAOptimal <= amountADesired);
        (amountA, amountB) = (amountAOptimal, amountBDesired);
      }
    }
  }
}

