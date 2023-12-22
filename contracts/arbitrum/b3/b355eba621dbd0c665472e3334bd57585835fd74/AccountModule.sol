/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

import "./IAccountTokenModule.sol";
import "./IAccountModule.sol";
import "./AssociatedSystem.sol";
import "./Account.sol";
import "./AccountRBAC.sol";

/**
 * @title Account Manager.
 * @dev See IAccountModule.
 */
contract AccountModule is IAccountModule {
    using SetUtil for SetUtil.AddressSet;
    using SetUtil for SetUtil.Bytes32Set;
    using AccountRBAC for AccountRBAC.Data;
    using Account for Account.Data;

    bytes32 private constant _ACCOUNT_SYSTEM = "accountNFT";

    /**
     * @inheritdoc IAccountModule
     */
    function getAccountTokenAddress() public view override returns (address) {
        return AssociatedSystem.load(_ACCOUNT_SYSTEM).proxy;
    }

    /**
     * @inheritdoc IAccountModule
     */
    function getAccountPermissions(uint128 accountId)
        external
        view
        returns (AccountPermissions[] memory accountPerms)
    {
        AccountRBAC.Data storage accountRbac = Account.load(accountId).rbac;

        uint256 allPermissionsLength = accountRbac.permissionAddresses.length();
        accountPerms = new AccountPermissions[](allPermissionsLength);
        for (uint256 i = 1; i <= allPermissionsLength; i++) {
            address permissionAddress = accountRbac.permissionAddresses.valueAt(i);
            accountPerms[i - 1] = AccountPermissions({
                user: permissionAddress,
                permissions: accountRbac.permissions[permissionAddress].values()
            });
        }
    }

    /**
     * @inheritdoc IAccountModule
     */
    function createAccount(uint128 requestedAccountId) external override {
        IAccountTokenModule accountTokenModule = IAccountTokenModule(getAccountTokenAddress());
        accountTokenModule.safeMint(msg.sender, requestedAccountId, "");
        Account.create(requestedAccountId, msg.sender);
        emit AccountCreated(requestedAccountId, msg.sender, block.timestamp);
    }

    /**
     * @inheritdoc IAccountModule
     */
    function notifyAccountTransfer(address to, uint128 accountId) external override {
        _onlyAccountToken();

        Account.Data storage account = Account.load(accountId);
        account.rbac.setOwner(to);
        emit AccountOwnerUpdate(accountId, to, block.timestamp);
    }

    /**
     * @inheritdoc IAccountModule
     */
    function hasPermission(uint128 accountId, bytes32 permission, address user) public view override returns (bool) {
        return Account.load(accountId).rbac.hasPermission(permission, user);
    }

    /**
     * @inheritdoc IAccountModule
     */
    function getAccountOwner(uint128 accountId) public view returns (address) {
        return Account.load(accountId).rbac.owner;
    }

    /**
     * @inheritdoc IAccountModule
     */
    function isAuthorized(uint128 accountId, bytes32 permission, address user) public view override returns (bool) {
        return Account.load(accountId).rbac.authorized(permission, user);
    }

    /**
     * @inheritdoc IAccountModule
     */
    function onlyAuthorized(uint128 accountId, bytes32 permission, address target) public view override {
        if (!isAuthorized(accountId, permission, target)) {
            revert PermissionNotGranted(accountId, AccountRBAC._ADMIN_PERMISSION, target);
        }
    }

    /**
     * @inheritdoc IAccountModule
     */
    function grantPermission(uint128 accountId, bytes32 permission, address user) external override {
        Account.Data storage account = Account.loadAccountAndValidateOwnership(accountId, msg.sender);

        account.rbac.grantPermission(permission, user);

        emit PermissionGranted(accountId, permission, user, msg.sender, block.timestamp);
    }

    /**
     * @inheritdoc IAccountModule
     */
    function revokePermission(uint128 accountId, bytes32 permission, address user) external override {
        Account.Data storage account = Account.loadAccountAndValidateOwnership(accountId, msg.sender);

        account.rbac.revokePermission(permission, user);

        emit PermissionRevoked(accountId, permission, user, msg.sender, block.timestamp);
    }

    /**
     * @inheritdoc IAccountModule
     */
    function renouncePermission(uint128 accountId, bytes32 permission) external override {
        if (!Account.load(accountId).rbac.hasPermission(permission, msg.sender)) {
            revert PermissionNotGranted(accountId, permission, msg.sender);
        }

        Account.load(accountId).rbac.revokePermission(permission, msg.sender);

        emit PermissionRevoked(accountId, permission, msg.sender, msg.sender, block.timestamp);
    }

    /**
     * @dev Reverts if the caller is not the account token managed by this module.
     */
    function _onlyAccountToken() internal view {
        if (msg.sender != address(getAccountTokenAddress())) {
            revert OnlyAccountTokenProxy(msg.sender);
        }
    }
}

