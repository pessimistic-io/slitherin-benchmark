// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./Ownable2StepUpgradeable.sol";
import "./IUnlimitedOwner.sol";

/**
 * @notice Implementation of the {IUnlimitedOwner} interface.
 *
 * @dev
 * This implementation acts as a simple central Unlimited owner oracle.
 * All Unlimited contracts should refer to this contract to check the owner of the Unlimited.
 */
contract UnlimitedOwner is IUnlimitedOwner, Ownable2StepUpgradeable {
    constructor() {
        _disableInitializers();
    }
    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable2Step_init();
    }

    /* ========== VIEWS ========== */

    /**
     * @notice checks if input is the Unlimited owner contract.
     *
     * @param user the address to check
     *
     * @return isOwner returns true if user is the Unlimited owner, else returns false.
     */
    function isUnlimitedOwner(address user) external view returns (bool isOwner) {
        if (user == owner()) {
            isOwner = true;
        }
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view override(IUnlimitedOwner, OwnableUpgradeable) returns (address) {
        return OwnableUpgradeable.owner();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice removed renounceOwnership function
     *
     * @dev
     * overrides OpenZeppelin renounceOwnership() function and reverts in all cases,
     * as Unlimited ownership should never be renounced.
     */
    function renounceOwnership() public view override onlyOwner {
        revert("UnlimitedOwner::renounceOwnership: Cannot renounce Unlimited ownership");
    }
}

