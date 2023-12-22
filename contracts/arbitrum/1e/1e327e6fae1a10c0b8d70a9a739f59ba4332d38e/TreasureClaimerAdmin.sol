//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { TreasureClaimerSettings, ClaimInfo, Initializable, ITreasureBadges } from "./TreasureClaimerSettings.sol";

abstract contract TreasureClaimerAdmin is Initializable, TreasureClaimerSettings {
    function __TreasureClaimerAdmin_init() internal onlyInitializing {
        __TreasureClaimerSettings_init();
    }

    function setTreasureBadges(address _badgeAddress) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        treasureBadgeCollection = ITreasureBadges(_badgeAddress);
    }

    function setSigningAuthority(address _signingAuthority) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        signingAuthority = _signingAuthority;
    }

    function undoClaim(ClaimInfo calldata _claimInfo) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        _undoIsClaimedStatus(_claimInfo);

        require(
            _claimInfo.badgeAddress == address(treasureBadgeCollection),
            "TreasureClaimer: badgeAddress does not match the current treasureBadgeCollection"
        );
        treasureBadgeCollection.adminBurn(_claimInfo.claimer, _claimInfo.badgeId, 1);

        emit BadgeUnclaimed(_claimInfo.claimer, _claimInfo.badgeAddress, _claimInfo.badgeId, _claimInfo.nonce);
    }

    function _undoIsClaimedStatus(ClaimInfo calldata _claimInfo) internal requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        require(isClaimed(_claimInfo), "TreasureClaimer: Cannot undo claim status of an unclaimed badge");
        _setIsClaimed(_claimInfo, false);
    }
}

