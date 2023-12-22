// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Metadata as IERC20} from "./extensions_IERC20Metadata.sol";
import {ICToken} from "./compound_ICToken.sol";
import {Addresses} from "./Addresses.sol";
import {ITenderPriceOracle} from "./ITenderPriceOracle.sol";
import {SafeMath} from "./SafeMath.sol";
import {IComptroller} from "./IComptroller.sol";
import {GLPHelper} from "./GLPHelper.sol";

library PriceHelper {
  using SafeMath for uint256;

  function getTotalValueUSD (
    IERC20[] memory tokens,
    uint[] memory amounts
  ) internal view returns (uint) {
    uint total = 0;
    for(uint i=0; i < tokens.length; i++) {
      total += getUSDValue(tokens[i], amounts[i]);
    }
    return total;
  }

  function getUSDValue(IERC20 token, uint amount) public view returns (uint) {
    return getUSDPerToken(token).mul(amount).div(10 ** token.decimals());
  }

  function getUSDPerToken(IERC20 token) public view returns (uint256) {
    ITenderPriceOracle oracle = ITenderPriceOracle(IComptroller(Addresses.unitroller).oracle());
    uint oraclePrice = oracle.getUSDPrice(token);
    uint256 oracleDecimals = oracle.getOracleDecimals(token);
    return oraclePrice.mul(10 ** (18 - oracleDecimals));
  }

  function getTokensPerUSD(IERC20 token) public view returns (uint256) {
    // return number of tokens that can be bought Per 1 USD
    uint256 scaledTokensPerUSD = uint256(1e36).div(getUSDPerToken(token));
    uint256 tokenDecimals = token.decimals();
    uint256 actualTokensPerUSD = scaledTokensPerUSD.div(10 ** (18 - tokenDecimals));
    return actualTokensPerUSD;
  }

  function getUSDPerUnderlying(ICToken token) public view returns (uint256) {
    return getUSDPerToken(token.underlying());
  }

  function getUnderlyingPerUSD(ICToken token) public view returns (uint256) {
    return getTokensPerUSD(token.underlying());
  }

  function getProportion(uint256 a, uint256 b) internal pure returns (uint256) {
    return a.mul(1e18).div(b);
  }

  // gives num token1 purchasable for 1 token 0
  function getTokens(IERC20 token0, IERC20 token1) public view returns (uint256) {
    uint256 usdPerToken0 = getUSDPerToken(token0);
    uint256 usdPerToken1 = getUSDPerToken(token1);
    return uint256(10 ** (token1.decimals() + 18)).div(getProportion(usdPerToken1, usdPerToken0));
  }

  // gives num token1 purchasable for numToken0 token0
  function getTokensForNumTokens(IERC20 token0, uint256 numToken0, IERC20 token1)
    public
    view
    returns (uint256)
  {
    uint256 token0ForToken1 = getTokens(token0, token1);
    uint256 numToken1ForNumToken0 = numToken0.mul(token0ForToken1).div(10 ** token0.decimals());
    return numToken1ForNumToken0;
  }
  // gives num token0 requred to purchase numtoken1 token1
  function getNumTokensForTokens(IERC20 token0, IERC20 token1, uint256 numToken1)
    public
    view
    returns (uint256)
  {
    uint256 token1ForToken0 = getTokens(token1, token0);
    uint256 numToken0ForNumToken1 = numToken1.mul(token1ForToken0).div(10 ** token1.decimals());
    return numToken0ForNumToken1;
  }
}

