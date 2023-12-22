// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./Math.sol";

import "./IGlpPriceFeed.sol";

import "./IGlpVault.sol";
import "./IGlpManager.sol";

/// @title Price Oracle
/// @author Christopher Enytc <wagmi@munchies.money>
/// @notice Works as router and provide utility functions for conversion
/// @dev All function calls are currently implemented
/// @custom:security-contact security@munchies.money
contract GlpPriceFeed is IGlpPriceFeed {
  using Math for uint256;

  address public immutable glpManager;

  address public immutable nativeToken;

  /**
   * @dev Set the glp manager address from GMX
   */
  constructor(address glpManager_, address nativeToken_) {
    require(
      glpManager_ != address(0),
      "GlpPriceFeed: glpManager_ cannot be address 0"
    );

    require(
      nativeToken_ != address(0),
      "GlpPriceFeed: nativeToken_ cannot be address 0"
    );

    glpManager = glpManager_;

    nativeToken = nativeToken_;
  }

  /// @notice Get latest price of GLP
  /// @dev Used to get tha latest price of GLP on the protocol
  /// @param maximise Boolean forward to contract call
  function getPrice(bool maximise) external view returns (uint256 price) {
    price = _getPrice(maximise);
  }

  /// @dev Call to gmx glp manager
  function _getPrice(bool maximise) internal view returns (uint256 price) {
    price = IGlpManager(glpManager).getPrice(maximise);
  }

  /// @notice Convert to USD
  /// @dev Used to convert an amount of GLP to USD
  /// @param amount Amount of GLP to be converted to USD
  /// @param maximise Boolean forward to contract call
  function convertToUSD(
    uint256 amount,
    bool maximise
  ) public view returns (uint256) {
    uint256 decimals = 18;
    uint256 price = _getPrice(maximise);

    uint256 convertedAmount = amount.mulDiv(price, 1 * 10 ** decimals);

    return convertedAmount;
  }

  /// @notice Convert to GLP
  /// @dev Used to convert an amount of USD to GLP
  /// @param asset Address of asset used for conversion
  /// @param amount Amount of USD to be converted to GLP
  /// @param maximise Boolean forward to contract call
  function convertToGLP(
    address asset,
    uint256 amount,
    bool maximise
  ) public view returns (uint256) {
    asset = asset == address(0)
      ? nativeToken // Native token address representation
      : asset;

    address vault = IGlpManager(glpManager).vault();

    uint256 minPrice = IGlpVault(vault).getMinPrice(asset);

    uint256 price = _getPrice(maximise);

    uint256 usdgAmount = amount.mulDiv(
      minPrice,
      IGlpVault(vault).PRICE_PRECISION()
    );

    usdgAmount = IGlpVault(vault).adjustForDecimals(
      usdgAmount,
      asset,
      IGlpVault(vault).usdg()
    );

    uint256 feeBasisPoints = IGlpVault(vault).getFeeBasisPoints(
      asset,
      usdgAmount,
      IGlpVault(vault).mintBurnFeeBasisPoints(),
      IGlpVault(vault).taxBasisPoints(),
      maximise
    );

    uint256 glpAmount = amount.mulDiv(minPrice, price);

    glpAmount = glpAmount.mulDiv(10_000 - feeBasisPoints, 10_000);

    return glpAmount;
  }

  /// @notice Get minimum price for GLP
  /// @dev Used to deposit funds to the integration contract
  /// @param amount Amount of asset token
  function getMinPrice(uint256 amount) external pure returns (uint256) {
    uint256 basisPointsDivisor = 10000;
    uint256 defaultSlippageAmount = 30;

    return
      amount.mulDiv(
        basisPointsDivisor - defaultSlippageAmount,
        basisPointsDivisor
      );
  }
}

