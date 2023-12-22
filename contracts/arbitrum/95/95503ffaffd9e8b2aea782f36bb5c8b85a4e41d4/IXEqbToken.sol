// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IXEqbToken {
  /**
   * @dev Initiates redeem process (xEQB to EQB)
   */
  function redeem(uint256 xEqbAmount, uint256 duration) external;

  /**
   * @dev Finalizes redeem process when vesting duration has been reached
   *
   * Can only be called by the redeem entry owner
   */
  function finalizeRedeem(uint256 redeemIndex) external;
}

