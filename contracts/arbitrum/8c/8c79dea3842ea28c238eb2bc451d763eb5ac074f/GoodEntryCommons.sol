// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./IGoodEntryOracle.sol";


/// @notice Commons for vaults and AMM positions for inheritance conflicts purposes
abstract contract GoodEntryCommons {
  /// @notice Vault underlying tokens
  ERC20 internal baseToken;
  ERC20 internal quoteToken;
  /// @notice Oracle address
  IGoodEntryOracle internal oracle;
}
