// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "./CErc20.sol";
import "./IERC20.sol";
import "./SafeMath.sol";

interface GlpManager{
  function getAumInUsdg(bool maximise) external view returns (uint256);
}

interface ChainLinkPriceOracle {
  function latestAnswer() external view returns (uint256);
  function decimals() external view returns (uint8);
}

contract TenderPriceOracle {
  using SafeMath for uint256;
  mapping(bytes32 => address) public Oracles;

  IERC20 public glpToken = IERC20(0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258);
  GlpManager public glpManager = GlpManager(0x321F653eED006AD1C29D174e17d96351BDe22649);

  constructor() {
    // assign the oracle for underlyingPrice to the symbol for each market
    Oracles[stringToBytes("tUSDT")] = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
    Oracles[stringToBytes("tUSDC")] = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    Oracles[stringToBytes("tLINK")] = 0x86E53CF1B870786351Da77A57575e79CB55812CB;
    Oracles[stringToBytes("tFRAX")] = 0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8;
    Oracles[stringToBytes("tWBTC")] = 0x6ce185860a4963106506C203335A2910413708e9;
    Oracles[stringToBytes("tETH")]  = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    Oracles[stringToBytes("tUNI")]  = 0x9C917083fDb403ab5ADbEC26Ee294f6EcAda2720;
    Oracles[stringToBytes("tETH")]  = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    Oracles[stringToBytes("tDAI")]  = 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;
    Oracles[stringToBytes("tGMX")]  = 0xDB98056FecFff59D032aB628337A4887110df3dB;
  }

  function stringToBytes (string memory s) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(s));
  }

  function getGlpSupply() public view returns (uint256) {
    return glpToken.totalSupply();
  }

  function getGlpAum() public view returns (uint256) {
    return glpManager.getAumInUsdg(true);
  }

  function getGlpPrice() public view returns (uint256) {
    // Formula taken from GLP docs
    return getGlpAum().mul(1e18).div(getGlpSupply());
  }
  function getUnderlyingDecimals(CToken ctoken) public view returns (uint) {
    if(stringToBytes(ctoken.symbol()) == stringToBytes("tETH")) {
      return 18;
    }
    address underlying = CErc20(address(ctoken)).underlying();
    return IERC20(underlying).decimals();
  }



  function getUnderlyingPrice(CToken ctoken) public view returns (uint) {
    bytes32 key = stringToBytes(ctoken.symbol());
    if(ctoken.isGLP()) {
      return getGlpPrice();
    }
    ChainLinkPriceOracle oracle = ChainLinkPriceOracle(Oracles[key]);
    // scale to USD value with 18 decimals
    return oracle.latestAnswer().mul(10**(28-getUnderlyingDecimals(ctoken)));
  }
}

