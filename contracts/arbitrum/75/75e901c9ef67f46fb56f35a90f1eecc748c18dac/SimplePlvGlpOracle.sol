// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;
import "./IERC20.sol";
import "./IERC4626.sol";

interface IGlpManager {
  function getAum(bool maximise) external view returns (uint256);
}

/**
 * @notice Key assumptions:
 * - GLP price from GlpManager is sufficiently robust
 * - Values returned in the oracle are precise to 1e12
 */
contract SimplePlvGlpOracle {
  uint256 public constant PRECISION = 1e12;
  IERC4626 public constant PlvGlp = IERC4626(0x5326E71Ff593Ecc2CF7AcaE5Fe57582D6e74CFF1);
  IERC20 public constant Glp = IERC20(0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258);
  IGlpManager public constant glpManager = IGlpManager(0x321F653eED006AD1C29D174e17d96351BDe22649);

  function getPlvGlpIndex1e12() public view returns (uint256) {
    return (PlvGlp.totalAssets() * PRECISION) / PlvGlp.totalSupply();
  }

  /// @dev getAum(true) is used in GlpManager
  /// https://arbiscan.io/address/0x321F653eED006AD1C29D174e17d96351BDe22649#code L917
  function getGlpPriceInUsd1e12(bool _maximise) public view returns (uint256) {
    return glpManager.getAum(_maximise) / IERC20(Glp).totalSupply();
  }

  function getPlvGlpPriceInUsd1e12(
    uint256 _plvGlpAmount
  ) external view returns (uint256 _priceInUsd1e18) {
    uint256 _glpAmount = (_plvGlpAmount * getPlvGlpIndex1e12()) / PRECISION;

    _priceInUsd1e18 = (_glpAmount * getGlpPriceInUsd1e12(true));
  }
}

