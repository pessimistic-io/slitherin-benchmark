// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {IRiskModule} from "./IRiskModule.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";

/**
 * @title IPriceOracle interface
 * @dev Interface for price oracles that returns the price (in Wad) for a given asset.
 *      It encapsulates the complexities of the underlying oracle, the validations and the reference currency used
 *      to express the price. That reference currency is implicit.
 * @author Ensuro
 */
interface IPriceOracle {
  /**
   * @dev Returns the price of the asset (the reference whether it's another crypto asset or USD is implicit)
   *
   * Requirements:
   * - The underlying oracle(s) are functional. It NEVER returns zero.
   *
   * @return The price of the asset in Wad (18 decimals)
   */
  function getCurrentPrice() external view returns (uint256);
}

