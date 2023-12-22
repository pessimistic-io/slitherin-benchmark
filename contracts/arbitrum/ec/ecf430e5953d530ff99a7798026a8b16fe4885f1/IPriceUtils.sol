// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PositionType} from "./PositionType.sol";

interface IPriceUtils {
  function glpPrice() external view returns (uint256);
  function perpPoolTokenPrice(address leveragedPoolAddress, PositionType positionType) external view returns (uint256);
}
