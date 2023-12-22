// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import {SafeMath} from "./SafeMath.sol";
import {Ownable} from "./Ownable.sol";
import {ICToken} from "./ICToken.sol";
import {IChainlinkPriceOracle} from "./IChainlinkPriceOracle.sol";
import {ITenderPriceOracle} from "./ITenderPriceOracle.sol";
import {IERC20Metadata as IERC20} from "./extensions_IERC20Metadata.sol";

contract TenderPriceOracle is ITenderPriceOracle, Ownable {
  using SafeMath for uint256;

  ICToken public constant tETH = ICToken(0x0706905b2b21574DEFcF00B5fc48068995FCdCdf);
  IERC20 public constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

  mapping(IERC20 => IChainlinkPriceOracle) public Oracles;

  constructor() {
    Oracles[IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9)] =
      IChainlinkPriceOracle(0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7); // USDT
    Oracles[IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8)] =
      IChainlinkPriceOracle(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3); // USDC
    Oracles[IERC20(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4)] =
      IChainlinkPriceOracle(0x86E53CF1B870786351Da77A57575e79CB55812CB); // LINK
    Oracles[IERC20(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F)] =
      IChainlinkPriceOracle(0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8); // FRAX
    Oracles[IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f)] =
      IChainlinkPriceOracle(0x6ce185860a4963106506C203335A2910413708e9); // WBTC
    Oracles[IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1)] =
      IChainlinkPriceOracle(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612); // WETH
    Oracles[IERC20(0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0)] =
      IChainlinkPriceOracle(0x9C917083fDb403ab5ADbEC26Ee294f6EcAda2720); // UNI
    Oracles[IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1)] =
      IChainlinkPriceOracle(0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB); // DAI
    Oracles[IERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a)] =
      IChainlinkPriceOracle(0xDB98056FecFff59D032aB628337A4887110df3dB); // GMX
    Oracles[IERC20(0x539bdE0d7Dbd336b79148AA742883198BBF60342)] =
      IChainlinkPriceOracle(0x47E55cCec6582838E173f252D08Afd8116c2202d); // MAGIC
    Oracles[IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548)] =
      IChainlinkPriceOracle(0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6); // ARB
  }

  function getOracle(IERC20 token) public view returns (IChainlinkPriceOracle) {
    IChainlinkPriceOracle oracle = Oracles[token];
    require(address(oracle) != address(0), "Oracle not found for address");
    return oracle;
  }

  function setOracle(IERC20 underlying, IChainlinkPriceOracle oracle) public onlyOwner {
    Oracles[underlying] = oracle;
  }

  function getUnderlying(ICToken ctoken) public view returns (IERC20) {
    return (ctoken != tETH) ? ctoken.underlying() : WETH;
  }

  function getUnderlyingDecimals(ICToken ctoken) public view returns (uint256) {
    return IERC20(getUnderlying(ctoken)).decimals();
  }

  function getUnderlyingPrice(ICToken ctoken) public view returns (uint256) {
    return _getUnderlyingPrice(ctoken);
  }

  function _getUnderlyingPrice(ICToken ctoken) internal view returns (uint256) {
    IChainlinkPriceOracle oracle = getOracle(getUnderlying(ctoken));
    (, int256 answer,,,) = oracle.latestRoundData();
    require(answer > 0, "Oracle error");
    uint256 price = uint256(answer);
    // scale to USD value with 18 decimals
    uint256 totalDecimals = 36 - oracle.decimals();
    return price.mul(10 ** (totalDecimals - getUnderlyingDecimals(ctoken)));
  }

  function getOracleDecimals(IERC20 token) public view returns (uint256) {
    return getOracle(token).decimals();
  }

  function getUSDPrice(IERC20 token) public view returns (uint256) {
    (, int256 answer,,,) = getOracle(token).latestRoundData();
    require(answer > 0, "Oracle error");
    return uint256(answer);
  }
  // this will not be correct for compound but is used by vault for borrow calculations
}

