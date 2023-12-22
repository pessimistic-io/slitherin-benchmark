// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./Math.sol";

import "./IGlpManager.sol";

/// @title Price Oracle
/// @author Christopher Enytc <wagmi@munchies.money>
/// @notice Works as router and provide utility functions for conversion
/// @dev All function calls are currently implemented
/// @custom:security-contact security@munchies.money
contract GlpPriceFeed {
  address public immutable glpManager;

  /**
   * @dev Set the glp manager address from GMX
   */
  constructor(address glpManager_) {
    require(
      glpManager_ != address(0),
      "GlpPriceFeed: glpManager_ cannot be address 0"
    );

    glpManager = glpManager_;
  }

  /// @notice Get latest price of GLP
  /// @dev Used to get tha latest price of GLP on the protocol
  /// @param maximise Boolean forward to contract call
  function getPrice(bool maximise) public view returns (uint256 price) {
    price = _getPrice(maximise);
  }

  /// @dev Call to gmx glp manager
  function _getPrice(bool maximise) internal view returns (uint256 price) {
    price = IGlpManager(glpManager).getPrice(maximise);
  }

  /// @notice Convert to USD
  /// @dev Used to convert an amount of GLP to USD
  /// @param amount Amount of GLP to be converted to USD
  function convertToUSD(uint256 amount) public view returns (uint256) {
    uint256 decimals = 18;
    uint256 price = _getPrice(true);

    uint256 convertedAmount = Math.mulDiv(amount, price, 1 * 10 ** decimals); // F:[PO-7]

    return convertedAmount;
  }

  /// @notice Get minimum price for GLP
  /// @dev Used to deposit funds to the integration contract
  /// @param amount Amount of asset token
  function getMinPrice(uint256 amount) public pure returns (uint256) {
    uint256 basisPointsDivisor = 10000;
    uint256 defaultSlippageAmount = 30;

    return
      Math.mulDiv(
        amount,
        basisPointsDivisor - defaultSlippageAmount,
        basisPointsDivisor
      );
  }
}

