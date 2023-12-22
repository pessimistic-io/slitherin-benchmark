// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TokenExposure} from "./TokenExposure.sol";

interface IPositionManager {
  function PositionWorth() external view returns (uint256);
  function CostBasis() external view returns (uint256);
  function Pnl() external view returns (int256);
  function Exposures() external view returns (TokenExposure[] memory);

  function BuyPosition(uint256) external returns (uint256);
}
