// SPDX-License-Identifier: Business Source License 1.1
pragma solidity 0.8.18;

import {AccessControlEnumerableUpgradeable} from "./AccessControlEnumerableUpgradeable.sol";
import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";
import {EnumerableSetUpgradeable} from "./EnumerableSetUpgradeable.sol";
import {BaseUpgradeableModule} from "./BaseUpgradeableModule.sol";

import {IAuthorization} from "./IAuthorization.sol";
import {IHoldings} from "./IHoldings.sol";
import {IShareholderTransaction} from "./TransactionIfaces.sol";
import {IShareholderSelfServiceTransaction} from "./TransactionIfaces.sol";
import {ITransferAgentTransaction} from "./TransactionIfaces.sol";
import {ICancellableTransaction, ICancellableSelfServiceTransaction} from "./TransactionIfaces.sol";
import {ITransactionStorage} from "./TransactionIfaces.sol";

import {ModuleRegistry} from "./ModuleRegistry.sol";
import {TokenRegistry} from "./TokenRegistry.sol";

contract TransactionalModule is
    BaseUpgradeableModule,
    AccessControlEnumerableUpgradeable,
    IShareholderTransaction,
    IShareholderSelfServiceTransaction,
    ITransferAgentTransaction,
    ITransactionStorage,
    ICancellableTransaction,
    ICancellableSelfServiceTransaction
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /// @dev The Id for the current module used to register the module during deployment
    bytes32 public constant MODULE_ID = keccak256("MODULE_TRANSACTIONAL");
    /// @dev The owner role that can be granted to manage the current contract
    bytes32 public constant ROLE_MODULE_OWNER = keccak256("ROLE_MODULE_OWNER");
    /// @dev The Id of the authorization module
    bytes32 constant AUTHORIZATION_MODULE = keccak256("MODULE_AUTHORIZATION");

    event TransactionSubmitted(address indexed account, bytes32 transactionId);

    event TransactionCancelled(
        address indexed account,
        bytes32 transactionId,
        string memo
    );

    /// @dev Flag to enable/disable the Self Service API
    bool isSelfServiceOn;
    /// @dev Counter increased every time a new pending request is created
    uint256 requestsCounter;

    /// @dev Map of all the existing pending requests
    mapping(bytes32 => ITransactionStorage.TransactionDetail) transactionDetailMap;
    /// @dev Map of the list of pending requests id's per account
    mapping(address => EnumerableSetUpgradeable.Bytes32Set) pendingTransactionsMap;
    /// @dev Set containing the accounts with at least one pending requests
    EnumerableSetUpgradeable.AddressSet accountsWithTransactions;

    TokenRegistry tokenRegistry;
    /// @dev The Id of the token associated with the transaction requests of this contract
    /// At the moment only a default token Id can be provided during contract initialization
    /// but in the future more tokens could be used using the token registry
    string tokenId;

    // ---------------------- Modifiers ----------------------  //

    modifier onlyAdmin() {
        require(
            IAuthorization(modules.getModuleAddress(AUTHORIZATION_MODULE))
                .isAdminAccount(msg.sender),
            "CALLER_IS_NOT_AN_ADMIN"
        );
        _;
    }

    modifier onlyShareholderAsMsgSender() {
        require(
            IAuthorization(modules.getModuleAddress(AUTHORIZATION_MODULE))
                .isAccountAuthorized(msg.sender),
            "CALLER_IS_NOT_A_SHAREHOLDER"
        );
        _;
    }

    modifier onlyShareholder(address account) {
        require(
            IAuthorization(modules.getModuleAddress(AUTHORIZATION_MODULE))
                .isAccountAuthorized(account),
            "ACCOUNT_IS_NOT_A_SHAREHOLDER"
        );
        _;
    }

    modifier onlyWithSelfServiceOn() {
        require(isSelfServiceOn, "SELF_SERVICE_NOT_ENABLED");
        _;
    }

    modifier onlyHigherThanZero(uint256 amount) {
        require(amount > 0, "INVALID_AMOUNT");
        _;
    }

    modifier whenTransactionStorageIsEmpty(address account) {
        if (pendingTransactionsMap[account].length() == 0) {
            _;
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _moduleOwner,
        address _modRegistry,
        address _tokenRegistry,
        string memory _defaultToken
    ) public initializer {
        require(_moduleOwner != address(0), "INVALID_ADDRESS");
        require(_modRegistry != address(0), "INVALID_REGISTRY_ADDRESS");
        require(_tokenRegistry != address(0), "INVALID_REGISTRY_ADDRESS");
        __BaseUpgradeableModule_init();
        __AccessControlEnumerable_init();
        modules = ModuleRegistry(_modRegistry);
        tokenRegistry = TokenRegistry(_tokenRegistry);
        tokenId = _defaultToken;
        _grantRole(DEFAULT_ADMIN_ROLE, _moduleOwner);
        _setRoleAdmin(ROLE_MODULE_OWNER, ROLE_MODULE_OWNER);
        _grantRole(ROLE_MODULE_OWNER, _moduleOwner);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyRole(ROLE_MODULE_OWNER) {}

    // ---------------------- Self Service Control ----------------------  //

    /**
     * @notice Enables the Self Service API
     *
     * @dev Self Service allows shareholder accounts to call directly the associated API
     *      to create their own purchase, liquidation and cancellation requests
     *
     */
    function enableSelfService() external override onlyAdmin {
        isSelfServiceOn = true;
    }

    /**
     * @notice Disables the Self Service API
     *
     * @dev Self Service allows shareholder accounts to call directly the associated API
     *      to create their own purchase, liquidation and cancellation requests
     *
     */
    function disableSelfService() external override onlyAdmin {
        isSelfServiceOn = false;
    }

    /**
     * @notice Gets the current value of the Self Service API status
     *
     */
    function isSelfServiceEnabled() external view override returns (bool) {
        return isSelfServiceOn;
    }

    // ----------------- Self Service Transactions -----------------  //

    /**
     * @notice Creates a request by the shareholder to buy a certain number of shares equivalent to the given cash amount.
     *
     * The shareholder must be the caller and it must be previously authorized via the authorization API defined
     * by the {IAuthorization} interface.
     *
     * @param amount The cash amount equivalent to the number of shares to buy
     *
     */
    function requestSelfServiceCashPurchase(
        uint256 amount
    )
        external
        virtual
        override
        onlyWithSelfServiceOn
        onlyShareholderAsMsgSender
        onlyHigherThanZero(amount)
    {
        _createCashTransaction(
            msg.sender,
            ITransactionStorage.TransactionType.CASH_PURCHASE,
            true,
            block.timestamp,
            amount
        );
    }

    /**
     * @notice Creates a request by the shareholder to sell a certain number of shares equivalent to the given cash amount.
     *
     * The shareholder must be the caller and it must be previously authorized via the authorization API defined
     * by the {IAuthorization} interface.
     *
     * @param amount The cash amount equivalent to the number of shares to sell
     *
     */
    function requestSelfServiceCashLiquidation(
        uint256 amount
    )
        external
        virtual
        override
        onlyWithSelfServiceOn
        onlyShareholderAsMsgSender
    {
        require(
            IHoldings(tokenRegistry.getTokenAddress(tokenId)).hasEnoughHoldings(
                msg.sender,
                amount
            ),
            "NOT_ENOUGH_BALANCE"
        );
        _createCashTransaction(
            msg.sender,
            ITransactionStorage.TransactionType.CASH_LIQUIDATION,
            true,
            block.timestamp,
            amount
        );
    }

    /**
     * @notice Creates a request by the shareholder to sell the entire share holdings of the given account.
     *
     * The shareholder must be the caller and it must be previously authorized via the authorization API defined
     * by the {IAuthorization} interface.
     *
     */
    function requestSelfServiceFullLiquidation()
        external
        virtual
        override
        onlyWithSelfServiceOn
        onlyShareholderAsMsgSender
    {
        require(
            IHoldings(tokenRegistry.getTokenAddress(tokenId)).getShareHoldings(
                msg.sender
            ) > 0,
            "NOT_ENOUGH_BALANCE"
        );
        _createCashTransaction(
            msg.sender,
            ITransactionStorage.TransactionType.FULL_LIQUIDATION,
            true,
            block.timestamp,
            0 // No amount required
        );
    }

    /**
     * @notice Cancels an existing self service request for the calling shareholder.
     *
     * The shareholder's account must be previously authorized via the authorization API defined
     * by the {IAuthorization} interface.
     *
     * @dev The operation will revert if the request does not exist for the account or the caller
     *      is not an authorized shareholder.
     *
     * @param requestId The request ID
     * @param memo a memo for the calcellation
     *
     */
    function cancelSelfServiceRequest(
        bytes32 requestId,
        string memory memo
    ) external virtual override onlyShareholderAsMsgSender {
        require(
            transactionDetailMap[requestId].txType >
                ITransactionStorage.TransactionType.INVALID,
            "INVALID_TRANSACTION_TYPE"
        );
        require(
            transactionDetailMap[requestId].selfService,
            "INVALID_TRANSACTION_TYPE"
        );
        require(
            pendingTransactionsMap[msg.sender].contains(requestId),
            "INVALID_TRANSACTION_ID"
        );

        pendingTransactionsMap[msg.sender].remove(requestId);
        delete transactionDetailMap[requestId];

        if (pendingTransactionsMap[msg.sender].length() == 0) {
            accountsWithTransactions.remove(msg.sender);
        }

        emit TransactionCancelled(msg.sender, requestId, memo);
    }

    // -------------------- Shareholder Transactions --------------------  //

    /**
     * @notice Creates a request to buy a certain number of shares equivalent to the given cash amount.
     *
     * The shareholder must be previously authorized via the authorization API defined
     * by the {IAuthorization} interface.
     *
     * @param account The address of the shareholder's account
     * @param date The date of the request as a UNIX timestamp
     * @param amount The cash amount equivalent to the number of shares to buy
     *
     */
    function requestCashPurchase(
        address account,
        uint256 date,
        uint256 amount
    )
        external
        virtual
        override
        onlyAdmin
        onlyShareholder(account)
        onlyHigherThanZero(amount)
    {
        _createCashTransaction(
            account,
            ITransactionStorage.TransactionType.CASH_PURCHASE,
            false,
            date,
            amount
        );
    }

    /**
     * @notice Creates a request to sell a certain number of shares equivalent to the given cash amount.
     *
     * The shareholder must be previously authorized via the authorization API defined
     * by the {IAuthorization} interface.
     *
     * @param account The address of the shareholder's account
     * @param date The date of the request as a UNIX timestamp
     * @param amount The cash amount equivalent to the number of shares to sell
     *
     */
    function requestCashLiquidation(
        address account,
        uint256 date,
        uint256 amount
    ) external virtual override onlyAdmin onlyShareholder(account) {
        require(
            IHoldings(tokenRegistry.getTokenAddress(tokenId)).hasEnoughHoldings(
                account,
                amount
            ),
            "NOT_ENOUGH_BALANCE"
        );
        _createCashTransaction(
            account,
            ITransactionStorage.TransactionType.CASH_LIQUIDATION,
            false,
            date,
            amount
        );
    }

    /**
     * @notice Creates a request to sell the entire share holdings of the given account.
     *
     * The shareholder must be previously authorized via the authorization API defined
     * by the {IAuthorization} interface.
     *
     * @param account The address of the shareholder's account
     * @param date The date of the request as a UNIX timestamp
     *
     */
    function requestFullLiquidation(
        address account,
        uint256 date
    ) external virtual override onlyAdmin onlyShareholder(account) {
        require(
            IHoldings(tokenRegistry.getTokenAddress(tokenId)).getShareHoldings(
                account
            ) > 0,
            "NOT_ENOUGH_BALANCE"
        );
        _createCashTransaction(
            account,
            ITransactionStorage.TransactionType.FULL_LIQUIDATION,
            false,
            date,
            0 // No amount required
        );
    }

    /**
     * @notice Cancels an existing request for the given account.
     *
     * The shareholder's account must be previously authorized via the authorization API defined
     * by the {IAuthorization} interface.
     *
     * @dev The operation will revert if the request does not exist for the account or the caller
     *      is not the fund administrator.
     *
     * @param account The address of the shareholder's account
     * @param requestId The request ID
     * @param memo a memo for the calcellation
     *
     */
    function cancelRequest(
        address account,
        bytes32 requestId,
        string memory memo
    ) external virtual override onlyAdmin onlyShareholder(account) {
        require(
            transactionDetailMap[requestId].txType >
                ITransactionStorage.TransactionType.INVALID,
            "INVALID_TRANSACTION_TYPE"
        );
        require(
            pendingTransactionsMap[account].contains(requestId),
            "INVALID_TRANSACTION_ID"
        );

        pendingTransactionsMap[account].remove(requestId);
        delete transactionDetailMap[requestId];

        if (pendingTransactionsMap[account].length() == 0) {
            accountsWithTransactions.remove(account);
        }

        emit TransactionCancelled(account, requestId, memo);
    }

    // -------------------- TA Operations --------------------  //

    /**
     * @notice Creates a request to set up an Automatic Investent Plan for the given cash amount.
     *
     * The shareholder must be previously authorized via the authorization API defined
     * by the {IAuthorization} interface.
     *
     * @param account The address of the shareholder's account
     * @param date The date of the request as a UNIX timestamp
     * @param amount The cash amount equivalent to the number of shares to buy
     *
     */
    function setupAIP(
        address account,
        uint256 date,
        uint256 amount
    )
        external
        virtual
        override
        onlyAdmin
        onlyShareholder(account)
        onlyHigherThanZero(amount)
    {
        _createCashTransaction(
            account,
            ITransactionStorage.TransactionType.AIP,
            false,
            date,
            amount
        );
    }

    /**
     * @notice Removes an existing pending requests record for a given account
     *
     * @dev Only accounts or modules with ROLE_FUND_ADMIN or WRITE_ACCESS_TRANSACTION
     *      roles are allowed to call this function.
     * @dev The main usage for this function is to allow another module to modify
     *      the state of the current module.
     *
     * @param account The shareholder's account with the pending requests
     * @param requestId The Id of the pending request
     *
     */
    function clearTransactionStorage(
        address account,
        bytes32 requestId
    ) external virtual override returns (bool) {
        require(
            IAuthorization(modules.getModuleAddress(AUTHORIZATION_MODULE))
                .isAdminAccount(msg.sender) ||
                AccessControlUpgradeable(
                    modules.getModuleAddress(AUTHORIZATION_MODULE)
                ).hasRole(keccak256("WRITE_ACCESS_TRANSACTION"), msg.sender),
            "NO_WRITE_ACCESS"
        );
        delete transactionDetailMap[requestId];
        return pendingTransactionsMap[account].remove(requestId);
    }

    /**
     * @notice Removes an existing account from the list of accounts with transactions
     *
     * @dev This function will remove the given account from the list that contains all
     *      the accounts that have at least one pending transaction requests. This function
     *      should be called after validationg that the account as no more pending requests.
     *
     * @param account The shareholder's account
     *
     */
    function unlistFromAccountsWithPendingTransactions(
        address account
    ) external virtual override whenTransactionStorageIsEmpty(account) {
        require(
            IAuthorization(modules.getModuleAddress(AUTHORIZATION_MODULE))
                .isAdminAccount(msg.sender) ||
                AccessControlUpgradeable(
                    modules.getModuleAddress(AUTHORIZATION_MODULE)
                ).hasRole(keccak256("WRITE_ACCESS_TRANSACTION"), msg.sender),
            "NO_WRITE_ACCESS"
        );
        accountsWithTransactions.remove(account);
    }

    // -------------------- Views --------------------  //

    // The operations below will copy the storage used to memory, which can be quite expensive.
    // See: https://docs.openzeppelin.com/contracts/4.x/api/utils#EnumerableSet-values-struct-EnumerableSet-Bytes32Set-
    function getAccountTransactions(
        address account
    ) external view virtual override returns (bytes32[] memory) {
        return pendingTransactionsMap[account].values();
    }

    function getTransactionDetail(
        bytes32 requestId
    ) external view virtual override returns (uint8, uint256, uint256, bool) {
        return (
            uint8(transactionDetailMap[requestId].txType),
            transactionDetailMap[requestId].date,
            transactionDetailMap[requestId].amount,
            transactionDetailMap[requestId].selfService
        );
    }

    function getAccountsWithTransactions(
        uint256 pageSize
    ) external view virtual override returns (address[] memory accounts) {
        require(
            pageSize > 0 && pageSize <= accountsWithTransactions.length(),
            "INVALID_PAGINATION_SIZE"
        );

        accounts = new address[](pageSize);
        for (uint i = 0; i < pageSize; ) {
            accounts[i] = accountsWithTransactions.at(i);
            unchecked {
                i++;
            }
        }
    }

    function getAccountsWithTransactionsCount()
        external
        view
        virtual
        override
        returns (uint256)
    {
        return accountsWithTransactions.length();
    }

    function hasTransactions(
        address account
    ) external view virtual override returns (bool) {
        return accountsWithTransactions.contains(account);
    }

    function isFromAccount(
        address account,
        bytes32 requestId
    ) external view virtual override returns (bool) {
        return pendingTransactionsMap[account].contains(requestId);
    }

    function getVersion() external pure virtual override returns (uint8) {
        return 1;
    }

    // -------------------- Internal --------------------  //

    function _listAccountWithTransactions(address account) internal virtual {
        accountsWithTransactions.add(account);
    }

    function _unlistAccountWithTransactions(address account) internal virtual {
        accountsWithTransactions.remove(account);
    }

    function _createCashTransaction(
        address account,
        ITransactionStorage.TransactionType txType,
        bool selfService,
        uint256 date,
        uint256 amount
    ) internal virtual {
        requestsCounter += 1;
        bytes32 requestId = _getTxId(account, date);
        require(
            pendingTransactionsMap[account].add(requestId),
            "INVALID_TRANSACTION_ID"
        );
        accountsWithTransactions.add(account);
        transactionDetailMap[requestId].txType = txType;
        transactionDetailMap[requestId].date = date;
        transactionDetailMap[requestId].amount = amount;
        transactionDetailMap[requestId].selfService = selfService;

        emit TransactionSubmitted(account, requestId);
    }

    function _getTxId(
        address account,
        uint256 timestamp
    ) internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    block.number,
                    account,
                    timestamp,
                    requestsCounter
                )
            );
    }
}

