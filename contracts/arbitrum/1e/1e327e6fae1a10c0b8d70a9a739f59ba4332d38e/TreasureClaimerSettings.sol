//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { TreasureClaimerState, ClaimInfo, Initializable, ITreasureBadges } from "./TreasureClaimerState.sol";

abstract contract TreasureClaimerSettings is Initializable, TreasureClaimerState {
    function __TreasureClaimerSettings_init() internal onlyInitializing {
        __TreasureClaimerState_init();
    }

    function isClaimed(ClaimInfo calldata _claimInfo) public view returns (bool) {
        return claimInfoIsClaimed[_claimInfo.claimer][_claimInfo.badgeAddress][_claimInfo.badgeId][_claimInfo.nonce];
    }

    function _setIsClaimed(ClaimInfo calldata _claimInfo, bool _newStatus) internal {
        claimInfoIsClaimed[_claimInfo.claimer][_claimInfo.badgeAddress][_claimInfo.badgeId][_claimInfo.nonce] =
            _newStatus;
    }
}

