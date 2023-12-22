// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV3Pool.sol";
import "./IAmmPriceFeed.sol";
import "./FullMath.sol";
import "./IERC20Metadata.sol";

contract AmmPriceFeedV2 is IAmmPriceFeed,Ownable{
  uint8 public constant priceDecimals = 10;
  uint256 public constant PRICE_PRECISION = 10 ** priceDecimals;

  address public eth;
  address public ethUsd;
  mapping(address => address) public tokenPoolsV3;
  mapping(address => bool) public isToken0PoolsV3;

  constructor(
    address _eth,
    address _ethUsdPool,
    address[] memory _tokens, 
    address[] memory _poolsV3, 
    bool[] memory _isToken0Pools
  ) {
    eth = _eth;
    ethUsd = _ethUsdPool;
    _setTokenConfigs(_tokens, _poolsV3, _isToken0Pools);
  }

  function setTokenConfigs(
    address[] memory _tokens, 
    address[] memory _poolsV3, 
    bool[] memory _isToken0Pools
  ) public onlyOwner{
    _setTokenConfigs(_tokens, _poolsV3, _isToken0Pools);
  }

  function _setTokenConfigs(
    address[] memory _tokens, 
    address[] memory _poolsV3, 
    bool[] memory _isToken0Pools
  ) private {
    require(_tokens.length == _poolsV3.length);
    require(_tokens.length == _isToken0Pools.length);

    for (uint256 i = 0; i < _tokens.length; i++) {
      address token = _tokens[i];
      tokenPoolsV3[token] = _poolsV3[i];
      isToken0PoolsV3[token] = _isToken0Pools[i];
    }
  }

  function adjustForDecimals(uint256 _value, uint256 _decimalsDiv, uint256 _decimalsMul) public pure returns (uint256) {
    return _value * (10 ** _decimalsMul) / (10 ** _decimalsDiv);
  }

  function getPrice(address _token) public override view returns(uint256, uint8) {
    // ethUsd price
    (uint256 ethPrice, uint8 ethPriceDecimals) = getPriceV3(eth);
    ethPrice = adjustForDecimals(ethPrice, ethPriceDecimals, priceDecimals);
    if(_token == eth){
      return (ethPrice, priceDecimals);
    }

    // tokenEth price
    (uint256 tokenPrice, uint8 tokenPriceDecimals) = getPriceV3(_token);
    tokenPrice = adjustForDecimals(tokenPrice, tokenPriceDecimals, priceDecimals);
    
    uint256 price = ethPrice * tokenPrice / PRICE_PRECISION;
    return (price, priceDecimals);
  }

  function getPriceV3(address _token) public view returns (uint256, uint8) {
    address pool = tokenPoolsV3[_token];
    if(pool == address(0)){
      return (0,1);
    }

    bool isToken0 = isToken0PoolsV3[_token];
    uint8 token0Decimals = IERC20Metadata(IUniswapV3Pool(pool).token0()).decimals();
    uint8 token1Decimals = IERC20Metadata(IUniswapV3Pool(pool).token1()).decimals();

    (
      uint160 sqrtPriceX96,
      /*int24 tick*/,
      /*uint16 observationIndex*/,
      /*uint16 observationCardinality*/,
      /*uint16 observationCardinalityNext*/,
      /*uint8 feeProtocol*/,
      /*bool unlocked*/
    ) = IUniswapV3Pool(pool).slot0();
    uint256 q192 = 2 ** 192;
    uint256 qSqrtPriceX96 = uint256(sqrtPriceX96) ** 2;
    uint256 numerator0 = 10**token0Decimals;
    uint256 numerator1 = 10**token1Decimals;
    
    if(isToken0){
      uint256 price = FullMath.mulDiv(qSqrtPriceX96, numerator0, q192);
      price = price * numerator0;
      return (price, token0Decimals+token1Decimals);
    }else{
      uint256 price = FullMath.mulDiv(q192, numerator1, qSqrtPriceX96);
      price = price * numerator1;
      return (price, token0Decimals+token1Decimals);
    }
  }
}

