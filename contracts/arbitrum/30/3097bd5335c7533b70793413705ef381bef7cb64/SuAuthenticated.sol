// SPDX-License-Identifier: BSL 1.1

pragma solidity ^0.8.0;

import "./ISuAccessControl.sol";
import "./SuAccessRoles.sol";
import "./Initializable.sol";
import "./IERC165Upgradeable.sol";

/**
 * @title SuAuthenticated
 * @dev other contracts should inherit to be authenticated.
 * The address of SuAccessControlSingleton should be one for all contract that inherits SuAuthenticated
 */
abstract contract SuAuthenticated is Initializable, SuAccessRoles, IERC165Upgradeable {
    ISuAccessControl public ACCESS_CONTROL_SINGLETON;

    error OnlyDAOError();
    error OnlyAdminError();
    error OnlyAlerterError();
    error OnlyVaultAccessError();
    error OnlyLiquidationAccessError();
    error OnlyMintAccessError();
    error OnlyRewardAccessError();
    error OnlyRoleError();
    error BadAccessControlSingleton();

    /**
     * @dev should be passed in constructor
     */
    function __suAuthenticatedInit(address _accessControlSingleton) internal onlyInitializing {
        ACCESS_CONTROL_SINGLETON = ISuAccessControl(_accessControlSingleton);
        if (
            !ISuAccessControl(_accessControlSingleton).supportsInterface(type(IAccessControlUpgradeable).interfaceId)
        ) revert BadAccessControlSingleton();
    }

    /** CORE ROLES */

    modifier onlyDAO() {
        if (!ACCESS_CONTROL_SINGLETON.hasRole(DAO_ROLE, msg.sender)) revert OnlyDAOError();
        _;
    }

    modifier onlyAdmin() {
        if (!ACCESS_CONTROL_SINGLETON.hasRole(ADMIN_ROLE, msg.sender)) revert OnlyAdminError();
        _;
    }

    modifier onlyAlerter() {
        if (!ACCESS_CONTROL_SINGLETON.hasRole(ALERTER_ROLE, msg.sender)) revert OnlyAlerterError();
        _;
    }

    /** SYSTEM ROLES */

    modifier onlyVaultAccess() {
        if (!ACCESS_CONTROL_SINGLETON.hasRole(VAULT_ACCESS_ROLE, msg.sender)) revert OnlyVaultAccessError();
        _;
    }

    modifier onlyLiquidationAccess() {
        if (!ACCESS_CONTROL_SINGLETON.hasRole(LIQUIDATION_ACCESS_ROLE, msg.sender)) revert OnlyLiquidationAccessError();
        _;
    }

    modifier onlyMintAccess() {
        if (!ACCESS_CONTROL_SINGLETON.hasRole(MINT_ACCESS_ROLE, msg.sender)) revert OnlyMintAccessError();
        _;
    }

    modifier onlyRewardAccess() {
        if (!ACCESS_CONTROL_SINGLETON.hasRole(REWARD_ACCESS_ROLE, msg.sender)) revert OnlyRewardAccessError();
        _;
    }

    // syntax sugar under ACCESS_CONTROL_SINGLETON
    modifier onlyRole(bytes32 role) {
        if (!ACCESS_CONTROL_SINGLETON.hasRole(role, msg.sender)) revert OnlyRoleError();
        _;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return ACCESS_CONTROL_SINGLETON.supportsInterface(interfaceId);
    }
}

