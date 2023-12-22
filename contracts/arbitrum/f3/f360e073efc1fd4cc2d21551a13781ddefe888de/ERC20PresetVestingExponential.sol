// SPDX-License-Identifier: none
pragma solidity 0.8.19;

import "./ERC20Vesting.sol";
import "./ABDKMath64x64.sol";

/**
 * @dev Extension of ERC20Vesting with a reverse exponential unlock (unlock speed decreases over time rather than being linear)
 */
abstract contract ERC20PresetVestingExponential is ERC20Vesting {

  /// @notice Calculates the lockedAmount/unlockedAmount amounts according to reverse exponential unlock
  function _vestingStatus(uint256 vestedAmount, uint64 startTime) 
    internal view override returns (uint256 unlockedAmount, uint256 lockedAmount) 
  {
    // penalty function is (x^1.4 = e^(1.4*ln(x)), with x = 1 - elapsed / vestingDuration
    int128 elapsedRatio = ABDKMath64x64.divu(block.timestamp - startTime, vestingDuration());
    int128 lnElapsedRatio = ABDKMath64x64.ln(ABDKMath64x64.sub(1 << 64, elapsedRatio));
    int128 expo14 = int128(uint128(0x16666666666666666)); // 1.4 * 2**64
    int128 penaltyExponent = ABDKMath64x64.mul(expo14, lnElapsedRatio);
    int128 penaltyRatio = ABDKMath64x64.exp(penaltyExponent);
    lockedAmount = ABDKMath64x64.mulu(penaltyRatio, vestedAmount);
    unlockedAmount = vestedAmount - lockedAmount;
  }
  
}
