pragma solidity ^0.8.0;

import "./FullMath.sol";

library VestingMathLibrary {

    // gets the withdrawable amount from a lock
    function getWithdrawableAmount (uint256 startEmission, uint256 cliffEndEmission, uint256 endEmission, uint256 amount, uint256 timeStamp) internal pure returns (uint256) {
        // It is possible in some cases IUnlockCondition(condition).unlockTokens() will fail (func changes state or does not return a bool)
        // for this reason we implemented revokeCondition per lock so funds are never stuck in the contract.

        // Lock type 1 logic block (Normal Unlock on due date)
        if (startEmission == 0 || startEmission == endEmission || cliffEndEmission > timeStamp) {
            return 0;
        }
        // Lock type 2 logic block (Linear scaling lock)
        uint256 timeClamp = timeStamp;
        if (timeClamp > endEmission) {
            timeClamp = endEmission;
        }
        if (timeClamp < cliffEndEmission) {
            timeClamp = cliffEndEmission;
        }
        uint256 elapsed = timeClamp - cliffEndEmission;
        uint256 fullPeriod = endEmission - cliffEndEmission;
        return FullMath.mulDiv(amount, elapsed, fullPeriod); // fullPeriod cannot equal zero due to earlier checks and restraints when locking tokens (startEmission < endEmission)
    }
}

