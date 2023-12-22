// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IGMXRouter.sol";
import "./IGMXVault.sol";
import "./IGMXGLPManager.sol";
import "./IERC20.sol";


contract GMXOracle {
  /* ========== STATE VARIABLES ========== */

  // GMX router contract
  IGMXRouter public immutable gmxRouter;
  // GMX vault contract
  IGMXVault public immutable gmxVault;
  // GMX GLP manager contract
  IGMXGLPManager public immutable glpManager;

  /* ========== CONSTANTS ========== */

  address constant GLP = 0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _gmxRouter GMX router contract address
    * @param _gmxVault GMX vault contract address
    * @param _glpManager GMX GLP manager contract address
  */
  constructor(address _gmxRouter, address _gmxVault, address _glpManager) {
    require(_gmxRouter != address(0), "Invalid address");
    require(_gmxVault != address(0), "Invalid address");
    require(_glpManager != address(0), "Invalid address");

    gmxRouter = IGMXRouter(_gmxRouter);
    gmxVault = IGMXVault(_gmxVault);
    glpManager = IGMXGLPManager(_glpManager);
  }

  /* ========== VIEW FUNCTIONs ========== */

  /**
    * Used to get how much GLP in is required to get amtOut of tokenOut
    * @param _amtOut  Amount of tokenOut
    * @param _tokenIn  GLP
    * @param _tokenOut  Token to get out
    * @return  Amount of GLP in
  */
  function getGlpAmountIn(
    uint256 _amtOut,
    address _tokenIn,
    address _tokenOut
  ) public view returns (uint256) {
    require(_tokenIn == GLP, "Oracle tokenIn must be GLP");
    require(gmxVault.whitelistedTokens(_tokenOut), "Oracle tokenOut must be GMX whitelisted");

    uint256 BASIS_POINT_DIVISOR = gmxVault.BASIS_POINTS_DIVISOR(); //10000
    uint256 PRICE_PRECISION = gmxVault.PRICE_PRECISION(); // 1e30

    // get token out price from gmxVault which returns in 1e30
    uint256 tokenOutPrice = gmxVault.getMinPrice(_tokenOut) / 1e12;
    // get estimated value of tokenOut in usdg
    uint256 estimatedUsdgAmount = _amtOut * tokenOutPrice / 1e18;

    // get fee using estimatedUsdgAmount
    uint256 feeBasisPoints =  gmxVault.getFeeBasisPoints(
      _tokenOut,
      estimatedUsdgAmount,
      gmxVault.mintBurnFeeBasisPoints(),
      gmxVault.taxBasisPoints(),
      false
    );

    // reverse gmxVault _collectSwapFees
    // add 2 wei to ensure rounding up
    uint256 beforeFeeAmt = (_amtOut + 2) * BASIS_POINT_DIVISOR
                           / (BASIS_POINT_DIVISOR - feeBasisPoints);

    // reverse gmxVault adjustForDecimals
    uint256 beforeAdjustForDecimalsAmt = beforeFeeAmt * (10 ** 18)
                                         / (10 ** gmxVault.tokenDecimals(_tokenOut));

    // reverse gmxVault getRedemptionAmount
    uint256 usdgAmount = beforeAdjustForDecimalsAmt * gmxVault.getMaxPrice(_tokenOut)
                         / PRICE_PRECISION;

    // reverse glpManager _removeLiquidity
    uint256 aumInUsdg = glpManager.getAumInUsdg(false);
    uint256 glpSupply = IERC20(GLP).totalSupply();

    return usdgAmount * glpSupply / aumInUsdg;
  }
}

