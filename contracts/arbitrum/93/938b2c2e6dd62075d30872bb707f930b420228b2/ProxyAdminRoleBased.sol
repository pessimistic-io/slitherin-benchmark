// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ProxyAdmin.sol";
import "./AccessControlEnumerable.sol";

/**
 * @notice DISCLAIMER: Forked from OpenZeppelin. Use at your own risk.
 */

/**
 * @dev This is an auxiliary contract meant to be assigned as the admin of a {TransparentUpgradeableProxy}. For an
 * explanation of why you would want to use this see the documentation for {TransparentUpgradeableProxy}.
 */
contract ProxyAdminRoleBased is ProxyAdmin, AccessControlEnumerable {
    bytes32 public constant UPGRADE_ROLE = keccak256("UPGRADE_ROLE");

    constructor(address[] memory _upgraders) {
        _grantUpgradeRole(_upgraders);
    }

    /**
     * @dev Modifier that requires the caller to have a specific role or be the owner.
     */
    modifier onlyOwnerOrRole(bytes32 role) {
        require(hasRole(role, _msgSender()) || owner() == _msgSender(), "Caller is not a role holder or owner");
        _;
    }

    /**
     * onlyOwner functions
     */

    function revokeUpgradeRole(address[] memory _upgraders) external onlyOwner {
        for (uint i = 0; i < _upgraders.length; i++) {
            _revokeRole(UPGRADE_ROLE, _upgraders[i]);
        }
    }

    function grantUpgradeRole(address[] memory _upgraders) external onlyOwner {
        _grantUpgradeRole(_upgraders);
    }

    function _grantUpgradeRole(address[] memory _upgraders) internal {
        for (uint i = 0; i < _upgraders.length; i++) {
            _grantRole(UPGRADE_ROLE, _upgraders[i]);
        }
    }

    /**
     * UPGRADE_ROLE functions
     */

    /**
     * @dev Upgrades `proxy` to `implementation`. See {TransparentUpgradeableProxy-upgradeTo}.
     *
     * Requirements:
     *
     * - This contract must be the admin of `proxy`.
     */
    function upgrade(
        ITransparentUpgradeableProxy proxy,
        address implementation
    ) public virtual override onlyOwnerOrRole(UPGRADE_ROLE) {
        proxy.upgradeTo(implementation);
    }

    /**
     * @dev Upgrades `proxy` to `implementation` and calls a function on the new implementation. See
     * {TransparentUpgradeableProxy-upgradeToAndCall}.
     *
     * Requirements:
     *
     * - This contract must have the `UPGRADE_ROLE`.
     */
    function upgradeAndCall(
        ITransparentUpgradeableProxy proxy,
        address implementation,
        bytes memory data
    ) public payable virtual override onlyOwnerOrRole(UPGRADE_ROLE) {
        proxy.upgradeToAndCall{value: msg.value}(implementation, data);
    }
}

