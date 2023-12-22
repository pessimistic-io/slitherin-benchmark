// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;
pragma experimental ABIEncoderV2;

// propose pools to users according to their balances on front-end
// change router into allowancetarget to be more parametric in case router changes
// add withdraw functions to withdraw any balance left (ETH and ERC20)
// solidly : change ISwapPair

import "./ISwapPair.sol";
import "./ISwapFactory.sol";
import "./IRouter.sol";
import "./IWETH.sol";
import "./SwapPair.sol";
import "./Babylonian.sol";
import "./interfaces_IERC20.sol";

contract Zap {
  address public immutable router;
  address public immutable factory;
  address public immutable weth;

  constructor(
    address _router,
    address _factory,
    address _weth
  ) {
    router = _router;
    factory = _factory;
    weth = _weth;
  }

  event zappedOut(address indexed _zapper, address indexed _pool, address indexed _token, uint256 _amountOut);
  event zappedIn(address indexed _zapper, address indexed _pool, address indexed _token, uint256 _poolTokens);

  receive() external payable {}

  fallback() external payable {}

  // ***** ZAP METHODS *****

  function zapIn(
    address _token,
    uint256 _amount,
    address _pool,
    uint256 _minPoolTokens,
    bytes memory _swapData,
    address _to
  ) public payable virtual returns (uint256 poolTokens) {
    uint256 toInvest_;
    if (_token == address(0)) {
      require(msg.value > 0, "no ETH sent");
      toInvest_ = msg.value;
    } else {
      require(msg.value == 0, "ETH sent");
      require(_amount > 0, "invalid amount");
      IERC20(_token).transferFrom(msg.sender, address(this), _amount);
      toInvest_ = _amount;
    }

    (address _token0, address _token1) = _getTokens(_pool);
    bool stable_ = ISwapPair(_pool).stable();

    address tempToken_;
    uint256 tempAmount_;

    if (_token != _token0 && _token != _token1) {
      (tempToken_, tempAmount_) = _swapIn(_token, _pool, toInvest_, _swapData);
    } else {
      (tempToken_, tempAmount_) = (_token, _amount);
    }

    (uint256 amount0_, uint256 amount1_) = _swapOptimalAmount(
      tempToken_,
      _pool,
      _token0,
      _token1,
      tempAmount_,
      stable_
    );
    poolTokens = _provideLiquidity(_token0, _token1, amount0_, amount1_, stable_, _to);
    require(poolTokens >= _minPoolTokens, "not enough LP tokens received");

    emit zappedIn(_to, _pool, _token, poolTokens);
  }

  function zapOut(
    address _tokenOut,
    address _pool,
    uint256 _poolTokens,
    uint256 _amountOutMin,
    bool _stable,
    bytes[] memory _swapData,
    address _to
  ) public virtual returns (uint256 amountOut) {
    require(_poolTokens > 0, "invalid amount");
    ISwapPair(_pool).transferFrom(msg.sender, address(this), _poolTokens);
    (uint256 amount0_, uint256 amount1_) = _withdrawLiquidity(_pool, _poolTokens, _stable);

    amountOut = _swapTokens(_pool, amount0_, amount1_, _tokenOut, _swapData);
    require(amountOut >= _amountOutMin, "high slippage");

    if (_tokenOut == address(0)) {
      payable(_to).transfer(amountOut);
    } else {
      IERC20(_tokenOut).transfer(_to, amountOut);
    }
    emit zappedOut(_to, _pool, _tokenOut, amountOut);
  }

  // ***** INTERNAL *****

  function _getTokens(address _pool) internal view returns (address token0, address token1) {
    (token0, token1) = ISwapPair(_pool).tokens();
  }

  function _getOptimalAmount(
    uint256 r,
    uint256 a,
    bool stable
  ) internal pure returns (uint256) {
    return stable ? a / 2 : (Babylonian.sqrt(r * (r * 398920729 + a * 398920000)) - r * (19973)) / 19946;
  }

  function _swapOptimalAmount(
    address _tokenIn,
    address _pool,
    address _token0,
    address _token1,
    uint256 _amount,
    bool _stable
  ) internal returns (uint256 amount0, uint256 amount1) {
    ISwapPair pair = ISwapPair(_pool);
    (uint256 reserve0_, uint256 reserve1_, ) = pair.getReserves();
    if (_tokenIn == _token0) {
      uint256 optimalAmount = _getOptimalAmount(reserve0_, _amount, _stable);
      if (optimalAmount <= 0) {
        optimalAmount = _amount / 2;
      }

      amount1 = _swapTokensForTokens(_tokenIn, _token1, optimalAmount, _stable);
      amount0 = _amount - optimalAmount;
    } else {
      uint256 optimalAmount = _getOptimalAmount(reserve1_, _amount, _stable);
      if (optimalAmount <= 0) {
        optimalAmount = _amount / 2;
      }

      amount0 = _swapTokensForTokens(_tokenIn, _token0, optimalAmount, _stable);
      amount1 = _amount - optimalAmount;
    }
  }

  function _swapIn(
    address _token,
    address _pool,
    uint256 _amount,
    bytes memory _swapData
  ) internal returns (address tokenOut, uint256 amountOut) {
    uint256 value_;
    IERC20 token_ = IERC20(_token);
    if (_token == address(0)) {
      value_ = _amount;
    } else {
      token_.approve(address(router), 0);
      token_.approve(address(router), _amount + 1);
    }
    (address token0_, address token1_) = _getTokens(_pool);
    IERC20 token0 = IERC20(token0_);
    uint256 preBalance0 = token0.balanceOf(address(this));
    // _to parameter in _swapData MUST be set to the address of this contract
    (bool success, bytes memory data) = address(router).call{ value: value_ }(_swapData);
    require(success, "error entering pair");
    uint256[] memory out = abi.decode(data, (uint256[]));
    amountOut = out[out.length - 1];
    require(amountOut > 0, "amount too low entering pair");
    uint256 postBalance0 = token0.balanceOf(address(this));
    preBalance0 != postBalance0 ? tokenOut = token0_ : tokenOut = token1_;
  }

  function _swapOut(
    address _tokenIn,
    address _tokenOut,
    uint256 _amount,
    bytes memory _swapData
  ) internal returns (uint256 amountOut) {
    if (_tokenIn == weth && _tokenOut == address(0)) {
      IWETH(weth).withdraw(_amount);
      return _amount;
    }
    uint256 value_;
    if (_tokenIn == address(0)) {
      value_ = _amount;
    } else {
      IERC20(_tokenIn).approve(address(router), _amount);
    }
    uint256 preBalance = _tokenOut == address(0) ? address(this).balance : IERC20(_tokenOut).balanceOf(address(this));

    (bool success, ) = address(router).call{ value: value_ }(_swapData);
    require(success, "error swapping tokens");

    amountOut =
      (_tokenOut == address(0) ? address(this).balance : IERC20(_tokenOut).balanceOf(address(this))) -
      preBalance;
    require(amountOut > 0, "wapped to Invalid Intermediate");
  }

  function _swapTokens(
    address _pool,
    uint256 _amount0,
    uint256 _amount1,
    address _tokenOut,
    bytes[] memory _swapData
  ) internal returns (uint256 amountOut) {
    (address token0_, address token1_) = _getTokens(_pool);
    if (token0_ == _tokenOut) {
      amountOut += _amount0;
    } else {
      amountOut += _swapOut(token0_, _tokenOut, _amount0, _swapData[0]);
    }

    if (token1_ == _tokenOut) {
      amountOut += _amount1;
    } else {
      amountOut += _swapOut(token1_, _tokenOut, _amount1, _swapData[1]);
    }
  }

  function _swapTokensForTokens(
    address _tokenIn,
    address _tokenOut,
    uint256 _amount,
    bool _stable
  ) internal returns (uint256 amountOut) {
    require(_tokenIn != _tokenOut, "tokens are the same");
    require(ISwapFactory(factory).getPair(_tokenIn, _tokenOut, _stable) != address(0), "pair does not exist");
    IERC20(_tokenIn).approve(address(router), 0);
    IERC20(_tokenIn).approve(address(router), _amount);
    route[] memory routes = new route[](1);
    routes[0] = route(_tokenIn, _tokenOut, _stable);
    amountOut = IRouter(router).swapExactTokensForTokens(_amount, 1, routes, address(this), block.timestamp)[1];
    require(amountOut > 0, "amount out too low");
  }

  function _provideLiquidity(
    address _token0,
    address _token1,
    uint256 _amount0,
    uint256 _amount1,
    bool _stable,
    address _to
  ) internal returns (uint256) {
    IERC20(_token0).approve(address(router), 0);
    IERC20(_token1).approve(address(router), 0);
    IERC20(_token0).approve(address(router), _amount0);
    IERC20(_token1).approve(address(router), _amount1);
    (uint256 amountA, uint256 amountB, uint256 poolTokens) = IRouter(router).addLiquidity(
      _token0,
      _token1,
      _stable,
      _amount0,
      _amount1,
      1,
      1,
      _to,
      block.timestamp
    );
    // Returning Residue in token0, if any
    if (_amount0 - amountA > 0) {
      IERC20(_token0).transfer(msg.sender, _amount0 - amountA);
    }
    // Returning Residue in token1, if any
    if (_amount1 - amountB > 0) {
      IERC20(_token1).transfer(msg.sender, _amount1 - amountB);
    }
    return poolTokens;
  }

  function _withdrawLiquidity(
    address _pool,
    uint256 _poolTokens,
    bool _stable
  ) internal returns (uint256 amount0, uint256 amount1) {
    require(_pool != address(0), "this pool does not exist");
    (address token0_, address token1_) = ISwapPair(_pool).tokens();
    IERC20(_pool).approve(router, _poolTokens);
    (amount0, amount1) = IRouter(router).removeLiquidity(
      token0_,
      token1_,
      _stable,
      _poolTokens,
      1,
      1,
      address(this),
      block.timestamp
    );
    require(amount0 > 0 && amount1 > 0, "removed insufficient liquidity");
  }

  function withdraw() public {}
}

