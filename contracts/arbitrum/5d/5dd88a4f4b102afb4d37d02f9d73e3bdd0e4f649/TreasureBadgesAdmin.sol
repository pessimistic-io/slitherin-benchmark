//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TreasureBadgesState.sol";

abstract contract TreasureBadgesAdmin is Initializable, TreasureBadgesState {
    function __TreasureBadgesAdmin_init() internal onlyInitializing {
        TreasureBadgesState.__TreasureBadgesState_init();
    }

    function adminMint(
        address _to,
        uint256 _id
    ) external override whenNotPaused requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        _mint(_to, _id, 1, "");
    }

    function adminBurn(
        address _from,
        uint256 _id,
        uint256 _amount
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        _burn(_from, _id, _amount);
    }
}

