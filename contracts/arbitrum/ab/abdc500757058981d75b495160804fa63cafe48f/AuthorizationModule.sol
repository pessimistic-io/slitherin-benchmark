// SPDX-License-Identifier: Business Source License 1.1
pragma solidity 0.8.18;

import {AccessControlEnumerableUpgradeable} from "./AccessControlEnumerableUpgradeable.sol";
import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";
import {BaseUpgradeableModule} from "./BaseUpgradeableModule.sol";
import {IAccessControlUpgradeable} from "./IAccessControlUpgradeable.sol";
import {IAuthorization} from "./IAuthorization.sol";
import {ITransactionStorage} from "./TransactionIfaces.sol";
import {IHoldings} from "./IHoldings.sol";
import {TokenRegistry} from "./TokenRegistry.sol";

import {ModuleRegistry} from "./ModuleRegistry.sol";

contract AuthorizationModule is
    BaseUpgradeableModule,
    AccessControlEnumerableUpgradeable,
    IAuthorization
{
    bytes32 public constant MODULE_ID = keccak256("MODULE_AUTHORIZATION");
    bytes32 public constant ROLE_MODULE_OWNER = keccak256("ROLE_MODULE_OWNER");
    bytes32 public constant ROLE_AUTHORIZATION_ADMIN =
        keccak256("ROLE_AUTHORIZATION_ADMIN");
    bytes32 public constant ROLE_FUND_ADMIN = keccak256("ROLE_FUND_ADMIN");
    bytes32 public constant ROLE_FUND_AUTHORIZED =
        keccak256("ROLE_FUND_AUTHORIZED");
    // Inter-module comm
    bytes32 public constant WRITE_ACCESS_TRANSACTION =
        keccak256("WRITE_ACCESS_TRANSACTION");
    bytes32 public constant WRITE_ACCESS_TOKEN =
        keccak256("WRITE_ACCESS_TOKEN");

    address tokenAddress;

    /// @dev This is emitted when an account is authorized
    event AccountAuthorized(address indexed account);
    /// @dev This is emitted when an account is deauthorized
    event AccountDeauthorized(address indexed account);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _moduleOwner,
        address _authAdmin,
        address _fundAdmin,
        address _modRegistry,
        address _tokenRegistry,
        string memory _defaultToken
    ) public initializer {
        require(
            _moduleOwner != address(0) &&
                _authAdmin != address(0) &&
                _fundAdmin != address(0),
            "INVALID_ADDRESS"
        );
        require(_modRegistry != address(0), "INVALID_REGISTRY_ADDRESS");
        require(_tokenRegistry != address(0), "INVALID_REGISTRY_ADDRESS");
        __BaseUpgradeableModule_init();
        __AccessControlEnumerable_init();
        modules = ModuleRegistry(_modRegistry);
        tokenAddress = TokenRegistry(_tokenRegistry).getTokenAddress(_defaultToken);
        require(tokenAddress != address(0), "INVALID_TOKEN_ADDRESS");

        _grantRole(DEFAULT_ADMIN_ROLE, _moduleOwner);
        _setRoleAdmin(ROLE_MODULE_OWNER, ROLE_MODULE_OWNER);
        _grantRole(ROLE_MODULE_OWNER, _moduleOwner);

        _setRoleAdmin(ROLE_AUTHORIZATION_ADMIN, ROLE_AUTHORIZATION_ADMIN);
        _grantRole(ROLE_AUTHORIZATION_ADMIN, _authAdmin);

        _setRoleAdmin(ROLE_FUND_ADMIN, ROLE_FUND_ADMIN);
        _grantRole(ROLE_FUND_ADMIN, _fundAdmin);

        _setRoleAdmin(ROLE_FUND_AUTHORIZED, ROLE_AUTHORIZATION_ADMIN);
        _setRoleAdmin(WRITE_ACCESS_TRANSACTION, ROLE_MODULE_OWNER);
        _setRoleAdmin(WRITE_ACCESS_TOKEN, ROLE_MODULE_OWNER);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyRole(ROLE_MODULE_OWNER) {}

    // -------------------- Account Management --------------------  //

    /**
     * @dev Grants the shareholder status to the given account.
     *
     * Only shareholders can have requests defined by the {ITransactionStorage} interface.
     *
     * @param account The address to grant the shareholder status
     *
     */
    function authorizeAccount(
        address account
    ) external virtual override onlyRole(ROLE_AUTHORIZATION_ADMIN) {
        require(account != address(0), "INVALID_ADDRESS");
        require(
            !hasRole(ROLE_FUND_AUTHORIZED, account),
            "SHAREHOLDER_ALREADY_EXISTS"
        );
        _grantRole(ROLE_FUND_AUTHORIZED, account);
        emit AccountAuthorized(account);
    }

    /**
     * @dev Revokes the shareholder status from the given account.
     *
     * Only shareholders can have requests defined by the {ITransactionStorage} interface.
     *
     * @param account The address to revoke the shareholder status from
     *
     */
    function deauthorizeAccount(
        address account
    ) external virtual override onlyRole(ROLE_AUTHORIZATION_ADMIN) {
        require(account != address(0), "INVALID_ADDRESS");
        address txModule = modules.getModuleAddress(
            keccak256("MODULE_TRANSACTIONAL")
        );
        require(txModule != address(0), "MODULE_REQUIRED_NOT_FOUND");
        require(
            hasRole(ROLE_FUND_AUTHORIZED, account),
            "SHAREHOLDER_DOES_NOT_EXISTS"
        );
        require(
            !ITransactionStorage(txModule).hasTransactions(account),
            "PENDING_TRANSACTIONS_EXIST"
        );
        require(
            IHoldings(tokenAddress).getShareHoldings(account) == 0,
            "ACCOUNT_HAS_BALANCE"
        );

        _revokeRole(ROLE_FUND_AUTHORIZED, account);
        emit AccountDeauthorized(account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been revoked `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`, the only exception to this rule is
     *   for accounts that have the role 'ROLE_FUND_AUTHORIZED', in such cases
     *   the function caller is required to have the role 'ROLE_AUTHORIZATION_ADMIN'
     *
     * May emit a {RoleRevoked} event.
     *
     */
    function renounceRole(
        bytes32 role,
        address account
    )
        public
        virtual
        override(AccessControlUpgradeable, IAccessControlUpgradeable)
    {
        if (role == ROLE_FUND_AUTHORIZED) {
            require(
                hasRole(ROLE_FUND_AUTHORIZED, account),
                "ACCOUNT_IS_NOT_A_SHAREHOLDER"
            );
            require(
                hasRole(ROLE_AUTHORIZATION_ADMIN, _msgSender()),
                "CALLER_IS_NOT_AN_ADMIN"
            );
        } else {
            require(
                account == _msgSender(),
                "AccessControl: can only renounce roles for self"
            );
        }

        _revokeRole(role, account);
    }

    // --------------------------- Views ---------------------------  //

    function isAccountAuthorized(
        address account
    ) external view virtual override returns (bool) {
        return hasRole(ROLE_FUND_AUTHORIZED, account);
    }

    function isAdminAccount(
        address account
    ) external view virtual override returns (bool) {
        return hasRole(ROLE_FUND_ADMIN, account);
    }

    function getAuthorizedAccountsCount()
        external
        view
        virtual
        override
        returns (uint256)
    {
        return getRoleMemberCount(ROLE_FUND_AUTHORIZED);
    }

    function getAuthorizedAccountAt(
        uint256 index
    ) external view virtual override returns (address) {
        return getRoleMember(ROLE_FUND_AUTHORIZED, index);
    }

    function getVersion() public pure virtual override returns (uint8) {
        return 1;
    }
}

