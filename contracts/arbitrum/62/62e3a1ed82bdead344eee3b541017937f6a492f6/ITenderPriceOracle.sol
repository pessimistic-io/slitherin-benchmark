// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import {ICToken} from "./compound_ICToken.sol";
import {IERC20Metadata as IERC20} from "./extensions_IERC20Metadata.sol";
import {IChainlinkPriceOracle} from "./IChainlinkPriceOracle.sol";

interface ITenderPriceOracle {
  function getOracleDecimals(IERC20 token) external view returns (uint256);
  function getUSDPrice(IERC20 token) external view returns (uint256);

  function getUnderlyingDecimals(ICToken ctoken) external view returns (uint256);
  function getUnderlyingPrice(ICToken ctoken) external view returns (uint256);

  function setOracle(IERC20 token, IChainlinkPriceOracle oracle) external;
}

