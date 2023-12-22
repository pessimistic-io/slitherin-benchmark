/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

/**
 * @title Account Manager Interface.
 * @notice Manages the system's account token NFT. Every user will need to register an account before being able to interact with
 * the protocol..
 */
interface IAccountModule {
    /**
     * @notice Thrown when the account interacting with the system is expected to be the associated account token, but is not.
     */
    error OnlyAccountTokenProxy(address origin);

    /**
     * @notice Thrown when an account attempts to renounce a permission that it didn't have.
     */
    error PermissionNotGranted(uint128 accountId, bytes32 permission, address user);

    /**
     * @notice Emitted when an account token with id `accountId` is minted to `owner`.
     * @param accountId The id of the account.
     * @param owner The address that owns the created account.
     * @param blockTimestamp The current block timestamp.
     */
    event AccountCreated(uint128 indexed accountId, address indexed owner, uint256 blockTimestamp);

    /**
     * @notice Emitted when an account token with id `accountId` is transferred to `newOwner`.
     * @param accountId The id of the account.
     * @param newOwner The address of the new owner.
     * @param blockTimestamp The current block timestamp.
     */
    event AccountOwnerUpdate(
        uint128 indexed accountId, 
        address indexed newOwner,
        uint256 blockTimestamp
    );

    /**
     * @notice Emitted when `user` is granted `permission` by `sender` for account `accountId`.
     * @param accountId The id of the account that granted the permission.
     * @param permission The bytes32 identifier of the permission.
     * @param user The target address to whom the permission was granted.
     * @param sender The Address that granted the permission.
     * @param blockTimestamp The current block timestamp.
     */
    event PermissionGranted(
        uint128 indexed accountId,
        bytes32 indexed permission,
        address indexed user,
        address sender,
        uint256 blockTimestamp
    );

    /**
     * @notice Emitted when `user` has `permission` renounced or revoked by `sender` for account `accountId`.
     * @param accountId The id of the account that has had the permission revoked.
     * @param permission The bytes32 identifier of the permission.
     * @param user The target address for which the permission was revoked.
     * @param sender The address that revoked the permission.
     * @param blockTimestamp The current block timestamp.
     */
    event PermissionRevoked(
        uint128 indexed accountId,
        bytes32 indexed permission,
        address indexed user,
        address sender,
        uint256 blockTimestamp
    );

    /**
     * @dev Data structure for tracking each user's permissions.
     */
    struct AccountPermissions {
        /**
         * @dev The address for which all the permissions are granted.
         */
        address user;
        /**
         * @dev The array of permissions given to the associated address.
         */
        bytes32[] permissions;
    }

    /**
     * @notice Returns an array of `AccountPermission` for the provided `accountId`.
     * @param accountId The id of the account whose permissions are being retrieved.
     * @return accountPerms An array of AccountPermission objects describing the permissions granted to the account.
     */
    function getAccountPermissions(uint128 accountId)
        external
        view
        returns (AccountPermissions[] memory accountPerms);

    /**
     * @notice Mints an account token with id `requestedAccountId` to `msg.sender`.
     * @param requestedAccountId The id requested for the account being created. Reverts if id already exists.
     *
     * Requirements:
     *
     * - `requestedAccountId` must not already be minted.
     *
     * Emits a {AccountCreated} event.
     */
    function createAccount(uint128 requestedAccountId) external;

    /**
     * @notice Called by AccountTokenModule to notify the system when the account token is transferred.
     * @dev Resets user permissions and assigns ownership of the account token to the new holder.
     * @param to The new holder of the account NFT.
     * @param accountId The id of the account that was just transferred.
     *
     * Requirements:
     *
     * - `msg.sender` must be the account token.
     */
    function notifyAccountTransfer(address to, uint128 accountId) external;

    /**
     * @notice Grants `permission` to `user` for account `accountId`.
     * @param accountId The id of the account that granted the permission.
     * @param permission The bytes32 identifier of the permission.
     * @param user The target address that received the permission.
     *
     * Requirements:
     *
     * - `msg.sender` must own the account token with ID `accountId` or have the "admin" permission.
     *
     * Emits a {PermissionGranted} event.
     */
    function grantPermission(uint128 accountId, bytes32 permission, address user) external;

    /**
     * @notice Revokes `permission` from `user` for account `accountId`.
     * @param accountId The id of the account that revoked the permission.
     * @param permission The bytes32 identifier of the permission.
     * @param user The target address that no longer has the permission.
     *
     * Requirements:
     *
     * - `msg.sender` must own the account token with ID `accountId` or have the "admin" permission.
     *
     * Emits a {PermissionRevoked} event.
     */
    function revokePermission(uint128 accountId, bytes32 permission, address user) external;

    /**
     * @notice Revokes `permission` from `msg.sender` for account `accountId`.
     * @param accountId The id of the account whose permission was renounced.
     * @param permission The bytes32 identifier of the permission.
     *
     * Emits a {PermissionRevoked} event.
     */
    function renouncePermission(uint128 accountId, bytes32 permission) external;

    /**
     * @notice Returns `true` if `user` has been granted `permission` for account `accountId`.
     * @param accountId The id of the account whose permission is being queried.
     * @param permission The bytes32 identifier of the permission.
     * @param user The target address whose permission is being queried.
     * @return hasPermission A boolean with the response of the query.
     */
    function hasPermission(uint128 accountId, bytes32 permission, address user)
        external
        view
        returns (bool hasPermission);

    /**
     * @notice Returns the address for the account token used by the manager.
     * @return accountNftToken The address of the account token.
     */
    function getAccountTokenAddress() external view returns (address accountNftToken);

    /**
     * @notice Returns the address that owns a given account, as recorded by the protocol.
     * @param accountId The account id whose owner is being retrieved.
     * @return owner The owner of the given account id.
     */
    function getAccountOwner(uint128 accountId) external view returns (address owner);

    /**
     * @notice Returns `true` if `target` is authorized to `permission` for account `accountId`.
     * @param accountId The id of the account whose permission is being queried.
     * @param permission The bytes32 identifier of the permission.
     * @param target The target address whose permission is being queried.
     * @return isAuthorized A boolean with the response of the query.
     */
    function isAuthorized(uint128 accountId, bytes32 permission, address target)
        external
        view
        returns (bool isAuthorized);

    /**
     * @notice Reverts if `target` is not authorized to `permission` for account `accountId`.
     * @param accountId The id of the account whose permission is being queried.
     * @param permission The bytes32 identifier of the permission.
     * @param target The target address whose permission is being queried.
     */
    function onlyAuthorized(uint128 accountId, bytes32 permission, address target) external view;
}

