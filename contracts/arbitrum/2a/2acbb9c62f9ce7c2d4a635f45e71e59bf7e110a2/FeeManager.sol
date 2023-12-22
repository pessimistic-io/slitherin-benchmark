// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

/* ========== STRUCTS ========== */

/**
 * @notice Represents a team in FeeManager.
 * @member id unique ID of the team
 * @member owner owner of the team
 * @member valid is the team valid
 */
struct Team {
    string id;
    address owner;
    bool valid;
}

/**
 * @dev Represents a balance of token for a team.
 * @member balance Amount deposited for team.
 * @member claimableWithdrawals Amount that can be withdrawn in the current cycle, i.e., requested in previous cycle.
 * @member unclaimableWithdrawals Amount that will become available for withdrawal in next cycle, i.e., requested in current cycle.
 * @member lastSynced Fee withdrawal cycle when this entry was last synced.
 */
struct BalanceBookEntry {
    uint256 balance;
    uint256 claimableWithdrawals;
    uint256 unclaimableWithdrawals;
    uint256 lastSynced;
}

/**
 * @notice Balance report for a team and token.
 * @member balance Amount deposited for team.
 * @member claimableWithdrawals Amount that can be withdrawn by team.
 * @member unclaimableWithdrawals Amount that was requested to be withdrawn by team. Will become claimable after fee collection.
 * @member collectableBalance Amount that can be collected for due fees for team (balance - claimableWithdrawals).
 * @member requestableBalance Amount that can be requested to be withdrawn by team (balance - claimableWithdrawals - unclaimableWithdrawals).
 */
struct BalanceReport {
    uint256 balance;
    uint256 claimableWithdrawals;
    uint256 unclaimableWithdrawals;
    uint256 collectableBalance;
    uint256 requestableBalance;
}

/* ========== CONTRACTS ========== */

/**
 * @title Fee management contract.
 * @notice This contract manages all aspects of fee collection:
 * - creation and managing of teams
 * - deposition and withdrawal of fees
 * - collection of fees
 * @dev Contract is Ownable and Upgradeable, and it uses SafeERC20 for token operations.
 */
contract FeeManager is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== EVENTS ========== */

    /**
     * @notice Event emitted when fee recipient is set.
     * @dev Emitted when `_setFeeRecipient` is called.
     * @param oldRecipient Address of old fee recipient.
     * @param newRecipient Address of new fee recipient.
     */
    event FeeRecipientSet(address indexed oldRecipient, address indexed newRecipient);

    /**
     * @notice Event emitted when new tokens are allowed for fee deposits.
     * @dev Emitted when `_allowTokens` is called.
     * @param tokens List of newly allowed tokens.
     */
    event TokensAllowed(IERC20Upgradeable[] tokens);

    /**
     * @notice Event emitted when current tokens are disallowed for fee deposits.
     * @dev Emitted when `disallowTokens` is called.
     * @param tokens List of newly disallowed tokens.
     */
    event TokensDisallowed(IERC20Upgradeable[] tokens);

    /**
     * @notice Event emitted when new addresses are allowed to collect fees.
     * @dev Emitted when `_addFeeCollectors` is called.
     * @param collectors List of newly allowed collectors.
     */
    event FeeCollectorsAdded(address[] collectors);

    /**
     * @notice Event emitted when current addresses are disallowed to collect fees.
     * @dev Emitted when `removeFeeCollectors` is called.
     * @param collectors List of newly disallowed collectors.
     */
    event FeeCollectorsRemoved(address[] collectors);

    /**
     * @notice Event emitted when new team is created.
     * @dev Emitted when `createTeam` is called.
     * @param indexedTeamId Hashed team ID.
     * @param teamId Team ID.
     */
    event TeamCreated(string indexed indexedTeamId, string teamId);

    /**
     * @notice Event emitted when team ownership is transfered.
     * @dev Emitted when `_transferTeamOwnership` is called.
     * @param teamId Hashed team ID.
     * @param previousOwner Address of previous team owner.
     * @param newOwner Address of new team owner.
     */
    event TeamOwnershipTransferred(
        string indexed teamId,
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @notice Event emitted when permissions for withdrawal for team are added.
     * @dev Emitted when `_addPermissionForWithdrawalForTeam` is called.
     * @param teamId Hashed team ID.
     * @param allowed List of addresses newly allowed to withdraw.
     */
    event WithdrawalPermissionForTeamAdded(string indexed teamId, address[] allowed);

    /**
     * @notice Event emitted when permissions for withdrawal for team are removed.
     * @dev Emitted when `removePermissionForWithdrawalForTeam` is called.
     * @param teamId Hashed team ID.
     * @param disallowed List of addresses disallowed to withdraw.
     */
    event WithdrawalPermissionForTeamRemoved(string indexed teamId, address[] disallowed);

    /**
     * @notice Event emitted when fee is deposited for team.
     * @dev Emitted when `depositFee` is called.
     * @param teamId Hashed team ID.
     * @param token Token deposited.
     * @param amount Amount deposited.
     */
    event FeeDeposited(
        string indexed teamId,
        IERC20Upgradeable indexed token,
        uint256 amount
    );

    /**
     * @notice Event emitted when fee is collected for team.
     * @dev Emitted when `collectFees` is called.
     * @param teamId Hashed team ID.
     * @param token Token collected.
     * @param amount Amount collected.
     */
    event FeeCollected(
        string indexed teamId,
        IERC20Upgradeable indexed token,
        uint256 amount
    );

    /**
     * @notice Event emitted when fee collection is completed.
     * @dev Emitted when `collectFees` is called.
     * @param feeCollectionCycle The new collection cycle started.
     */
    event FeeCollectionComplete(uint256 feeCollectionCycle);

    /**
     * @notice Event emitted when fee withdrawal is requested for team.
     * @dev Emitted when `requestFeeWithdrawal` is called.
     * @param teamId Hashed team ID.
     * @param token Token requested.
     * @param amount Amount requested.
     */
    event FeeWithdrawalRequested(
        string indexed teamId,
        IERC20Upgradeable indexed token,
        uint256 amount
    );

    /**
     * @notice Event emitted when fee withdrawal is claimed for team.
     * @dev Emitted when `claimFeeWithdrawal` is called.
     * @param teamId Hashed team ID.
     * @param token Token claimed.
     * @param amount Amount claimed.
     */
    event FeeWithdrawalClaimed(
        string indexed teamId,
        IERC20Upgradeable indexed token,
        uint256 amount
    );

    /* ========== CONSTANTS ========== */

    /**
     * @dev After this much time without a fee collection, teams will be able to
     * trigger new fee collection cycle in order to withdraw their funds.
     */
    uint256 private constant FEE_COLLECTION_INACTIVITY_LIMIT = 7 days;

    /* ========== STATE VARIABLES ========== */

    /// @notice Recipient of collected fees.
    address public feeRecipient;

    /**
     * @notice Current fee collection cycle.
     * @dev Used to keep track of withdrawal requests.
     */
    uint256 public feeCollectionCycle;

    /**
     * @notice Block timestamp when last fee collection was triggered.
     * @dev Used to determine when teams can trigger new fee collection cycle
     * in case of prolonged inactivity of fee collectors.
     */
    uint256 public lastFeeCollectionTime;

    /// @notice Tokens allowed to be used for fee deposits.
    mapping(IERC20Upgradeable => bool) public allowedTokens;
    /// @notice Addresses allowed to collect fees.
    mapping(address => bool) public feeCollectors;
    /// @notice Created teams.
    mapping(string => Team) public teams;
    /// @notice Who can withdraw fees for team.
    mapping(string => mapping(address => bool)) public withdrawalAllowList;
    /// @dev Balance for team-token.
    mapping(string => mapping(IERC20Upgradeable => BalanceBookEntry))
        private _balanceBook;

    /* ========== INITIALIZATION ========== */

    /**
     * @notice Sets initial state.
     * The address deploying the contract is automatically set as the owner.
     * @dev This replaces `constructor` (upgradeable contract).
     * Can only be called once.
     * Is called as part of deployment procedure.
     * Requirements:
     * - fee recipient should not be the zero address
     * @param _feeRecipient Recipient of collected fees.
     * @param _allowedTokens Tokens allowed to be used for fee deposits.
     */
    function initialize(
        address _feeRecipient,
        IERC20Upgradeable[] calldata _allowedTokens,
        address[] calldata _feeCollectors
    ) public initializer {
        // Call initializers for parent contracts.
        __Ownable_init();

        // Set initial state.
        _setFeeRecipient(_feeRecipient);
        _allowTokens(_allowedTokens);
        _addFeeCollectors(_feeCollectors);
        _updateLastFeeCollectionTime();
    }

    /* ========== CONTRACT MANAGEMENT FUNCTIONS ========== */

    /**
     * @notice Sets new address for fee recipient.
     * @dev Requirements:
     * - should be called by owner
     * - fee recipient should not be the zero address
     * @param _newFeeRecipient New fee recipient.
     */
    function setFeeRecipient(address _newFeeRecipient) external onlyOwner {
        _setFeeRecipient(_newFeeRecipient);
    }

    /**
     * @notice Allows tokens to be used for fee deposits.
     * @dev Requirements:
     * - should be called by owner
     * @param _allowedTokens Tokens to allow.
     */
    function allowTokens(IERC20Upgradeable[] calldata _allowedTokens) external onlyOwner {
        _allowTokens(_allowedTokens);
    }

    /**
     * @notice Disallows tokens to be used for fee deposits.
     * @dev Requirements:
     * - should be called by owner
     * @param _disallowedTokens Tokens to disallow.
     */
    function disallowTokens(IERC20Upgradeable[] calldata _disallowedTokens)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < _disallowedTokens.length; i++) {
            allowedTokens[_disallowedTokens[i]] = false;
        }

        emit TokensDisallowed(_disallowedTokens);
    }

    /**
     * @notice Adds new fee collectors.
     * @dev Requirements:
     * - should be called by owner
     * @param _feeCollectorsUpdate Fee collectors to add.
     */
    function addFeeCollectors(address[] calldata _feeCollectorsUpdate)
        external
        onlyOwner
    {
        _addFeeCollectors(_feeCollectorsUpdate);
    }

    /**
     * @notice Removes current fee collectors.
     * @dev Requirements:
     * - should be called by owner
     * @param _feeCollectorsUpdate Fee collectors to remove.
     */
    function removeFeeCollectors(address[] calldata _feeCollectorsUpdate)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < _feeCollectorsUpdate.length; i++) {
            feeCollectors[_feeCollectorsUpdate[i]] = false;
        }

        emit FeeCollectorsRemoved(_feeCollectorsUpdate);
    }

    /**
     * @dev Sets new fee recipient.
     * Checks that fee recipient is not the zero address.
     */
    function _setFeeRecipient(address _newFeeRecipient) private {
        require(
            _newFeeRecipient != address(0),
            "FeeManager::_setFeeRecipient: New fee recipient is the zero address."
        );

        address oldRecipient = feeRecipient;
        feeRecipient = _newFeeRecipient;

        emit FeeRecipientSet(oldRecipient, _newFeeRecipient);
    }

    /**
     * @dev Allows tokens to be used for fee deposits.
     */
    function _allowTokens(IERC20Upgradeable[] calldata _allowedTokens) private {
        for (uint256 i = 0; i < _allowedTokens.length; i++) {
            allowedTokens[_allowedTokens[i]] = true;
        }

        emit TokensAllowed(_allowedTokens);
    }

    /**
     * @dev Adds fee collectors.
     */
    function _addFeeCollectors(address[] calldata _feeCollectors) private {
        for (uint256 i = 0; i < _feeCollectors.length; i++) {
            feeCollectors[_feeCollectors[i]] = true;
        }

        emit FeeCollectorsAdded(_feeCollectors);
    }

    /**
     * @dev Updates last fee collection time to current block's timestamp.
     */
    function _updateLastFeeCollectionTime() private {
        lastFeeCollectionTime = block.timestamp;
    }

    /* ========== TEAM MANAGEMENT FUNCTIONS ========== */

    /**
     * @notice Creates a new team.
     * Team owner can mange the team and is allowed to withdraw fees.
     * @dev Requirements:
     * - should be called with unique `_teamId`.
     * - team owner should not be the zero address
     * @param _teamId Unique identifier for the team.
     * @param _teamOwner Team owner.
     * @param _withdrawalAllowList List of addresses that are allowed to withdraw fees for the team.
     */
    function createTeam(
        string calldata _teamId,
        address _teamOwner,
        address[] calldata _withdrawalAllowList
    ) external {
        require(!teams[_teamId].valid, "FeeManager::createTeam: Team already exists.");

        // Create the team.
        teams[_teamId] = Team({ id: _teamId, owner: address(0), valid: true });

        // Set everything for new team.
        _transferTeamOwnership(_teamId, _teamOwner);
        _addPermissionForWithdrawalForTeam(_teamId, _withdrawalAllowList);

        emit TeamCreated(_teamId, _teamId);
    }

    /**
     * @notice Transfers ownership of the team to a new owner.
     * @dev Requirements:
     * - should be called for a valid team
     * - should be called by team's owner
     * - new owner should not be the zero address
     * @param _teamId Team's identifier.
     * @param _newOwner New team owner.
     */
    function transferTeamOwnership(string calldata _teamId, address _newOwner)
        external
        isValidTeam(_teamId)
        onlyTeamOwner(_teamId)
    {
        _transferTeamOwnership(_teamId, _newOwner);
    }

    /**
     * @notice Adds addresses to the list of addresses that are allowed to withdraw fees for the team.
     * @dev Requirements:
     * - should be called for a valid team
     * - should be called by team's owner
     * @param _teamId Team identifier.
     * @param _withdrawalAllowListUpdate Whom to add permissions.
     */
    function addPermissionForWithdrawalForTeam(
        string calldata _teamId,
        address[] calldata _withdrawalAllowListUpdate
    ) external isValidTeam(_teamId) onlyTeamOwner(_teamId) {
        _addPermissionForWithdrawalForTeam(_teamId, _withdrawalAllowListUpdate);
    }

    /**
     * @notice Removes addresses from the list of addresses that are allowed to withdraw fees for the team.
     * @dev Requirements:
     * - should be called for a valid team
     * - should be called by team's owner
     * @param _teamId Team identifier.
     * @param _withdrawalAllowListUpdate Whom to remove permissions.
     */
    function removePermissionForWithdrawalForTeam(
        string calldata _teamId,
        address[] calldata _withdrawalAllowListUpdate
    ) external isValidTeam(_teamId) onlyTeamOwner(_teamId) {
        for (uint256 i = 0; i < _withdrawalAllowListUpdate.length; i++) {
            withdrawalAllowList[_teamId][_withdrawalAllowListUpdate[i]] = false;
        }

        emit WithdrawalPermissionForTeamRemoved(_teamId, _withdrawalAllowListUpdate);
    }

    /**
     * @notice Checks if a user is allowed to withdraw fees for the team.
     * Users are allowed to withdraw if
     * - they are the team owner
     * - they are on the withdrawal allow-list for the team
     * @dev Requirements:
     * - should be called for a valid team
     * @param _teamId Team identifier.
     * @param _user User whose permissions to check.
     * @return True, if user is allowed, false otherwise.
     */
    function isAllowedToWithdrawForTeam(string calldata _teamId, address _user)
        public
        view
        isValidTeam(_teamId)
        returns (bool)
    {
        return teams[_teamId].owner == _user || withdrawalAllowList[_teamId][_user];
    }

    /**
     * @dev Transfers ownership of the team to a new owner.
     * Checks that team owner is not the zero address.
     */
    function _transferTeamOwnership(string calldata _teamId, address _newOwner) private {
        require(
            _newOwner != address(0),
            "FeeManager::_transferTeamOwnership: New team owner is the zero address."
        );

        address oldOwner = teams[_teamId].owner;
        teams[_teamId].owner = _newOwner;

        emit TeamOwnershipTransferred(_teamId, oldOwner, _newOwner);
    }

    /**
     * @dev Adds addresses to the list of addresses that are allowed to withdraw fees for the team.
     */
    function _addPermissionForWithdrawalForTeam(
        string calldata _teamId,
        address[] calldata _withdrawalAllowListUpdate
    ) private {
        for (uint256 i = 0; i < _withdrawalAllowListUpdate.length; i++) {
            withdrawalAllowList[_teamId][_withdrawalAllowListUpdate[i]] = true;
        }

        emit WithdrawalPermissionForTeamAdded(_teamId, _withdrawalAllowListUpdate);
    }

    /* ========== BALANCE MANAGEMENT FUNCTIONS ========== */

    /**
     * @notice Deposits fee for a team.
     * Transaction of tokens must fist be approved by the caller on the token contract.
     * @dev Requirements:
     * - should be called for a valid team
     * - should be called with token from allow-list
     * This function must first sync balance book for team-token.
     * @param _teamId Team identifier.
     * @param _amount Amount to deposit.
     * @param _token Token to deposit.
     */
    function depositFee(
        string calldata _teamId,
        uint256 _amount,
        IERC20Upgradeable _token
    )
        external
        isValidTeam(_teamId)
        isAllowedToken(_token)
        syncBalanceBook(_teamId, _token)
    {
        // Transfer tokens and update balance.
        _token.safeTransferFrom(msg.sender, address(this), _amount);
        _balanceBook[_teamId][_token].balance += _amount;

        emit FeeDeposited(_teamId, _token, _amount);
    }

    /**
     * @notice Collects fees from teams.
     * Collected fees are transfered to the fee recipient.
     * Balance available for collection is `balance - claimableWithdrawals`.
     * @dev Requirements:
     * - should be called by owner
     * - should be called with parameters of equal length
     * - should be called with valid teams.
     * - team should have enough available balance
     * This function must first sync balance book for team-token before collection fees.
     * @param _teams Teams' identifiers.
     * @param _amounts Amounts to collect.
     * @param _tokens Tokens to collect.
     */
    function collectFees(
        string[] calldata _teams,
        uint256[] calldata _amounts,
        IERC20Upgradeable[] calldata _tokens
    ) external onlyFeeCollector {
        // Check that lenghts of parameters match.
        require(
            (_teams.length == _amounts.length) && (_teams.length == _tokens.length),
            "FeeManager::collectFees: Parameter length mismatch."
        );

        // Loop over each triplet.
        for (uint256 i = 0; i < _teams.length; i++) {
            // Check that the team is valid.
            _isValidTeam(_teams[i]);

            // Need to sync balance book for team-token to get currently available balance.
            _syncBalanceBook(_teams[i], _tokens[i]);

            // Check that there is enough balance for collection.
            require(
                _balanceBook[_teams[i]][_tokens[i]].balance -
                    _balanceBook[_teams[i]][_tokens[i]].claimableWithdrawals >=
                    _amounts[i],
                "FeeManager::collectFees: Not enough available balance left."
            );

            // Update balance and transfer tokens.
            unchecked {
                _balanceBook[_teams[i]][_tokens[i]].balance -= _amounts[i];
            }
            _tokens[i].safeTransfer(feeRecipient, _amounts[i]);

            emit FeeCollected(_teams[i], _tokens[i], _amounts[i]);
        }

        // Enter new fee collection cycle.
        feeCollectionCycle++;
        _updateLastFeeCollectionTime();
        emit FeeCollectionComplete(feeCollectionCycle);
        // Could sync at this point also, but it is not strictly needed.
    }

    /**
     * @notice Requests fee withdrawal.
     * This does not withdraw fees, but only requests withdrawal.
     * Fee withdrawal can be claimed in the next fee collection cycle.
     * Balance available for withdrawal request is
     * `balance - claimableWithdrawals - unclaimableWithdrawals`.
     * Multiple calls for same team-token will increase total requested amount.
     * @dev Requirements:
     * - should be called for a valid team
     * - should be called by user on withdrawal allow-list for the team
     * - team should have enough available balance
     * This function must first sync balance book for team-token.
     * @param _teamId Team identifier.
     * @param _amount Amount requested to withdraw.
     * @param _token Token requested to withdraw.
     */
    function requestFeeWithdrawal(
        string calldata _teamId,
        uint256 _amount,
        IERC20Upgradeable _token
    )
        external
        isValidTeam(_teamId)
        isAllowedToWithdraw(_teamId)
        syncBalanceBook(_teamId, _token)
    {
        // Check that there is enough available balance for withdrawal request.
        require(
            _balanceBook[_teamId][_token].balance -
                _balanceBook[_teamId][_token].claimableWithdrawals -
                _balanceBook[_teamId][_token].unclaimableWithdrawals >=
                _amount,
            "FeeManager::requestFeeWithdrawal: Not enough available balance left."
        );

        // Update balance.
        _balanceBook[_teamId][_token].unclaimableWithdrawals += _amount;

        emit FeeWithdrawalRequested(_teamId, _token, _amount);
    }

    /**
     * @notice Claims requested fee withdrawal.
     * Can claim up to amount requested in previous fee collection cycle.
     * Amount can be lowered by collected fees when requested amount
     * and fees were larger than available balance.
     * Can claim in multiple installments by multiple users.
     * @dev Requirements:
     * - should be called for a valid team
     * - should be called by user on withdrawal allow-list for the team
     * - team should have enough available balance
     * This function must first sync balance book for team-token.
     * @param _teamId Team identifier.
     * @param _amount Amount to claim.
     * @param _token Token to claim.
     */
    function claimFeeWithdrawal(
        string calldata _teamId,
        uint256 _amount,
        IERC20Upgradeable _token
    )
        external
        isValidTeam(_teamId)
        isAllowedToWithdraw(_teamId)
        syncBalanceBook(_teamId, _token)
    {
        BalanceBookEntry storage balanceBookEntry = _balanceBook[_teamId][_token];

        // Check that there is enough available balance for withdrawal claim.
        require(
            balanceBookEntry.claimableWithdrawals >= _amount,
            "FeeManager::claimFeeWithdrawal: Claimed amount is larger than requested amount."
        );

        // Update balance and transfer tokens.
        balanceBookEntry.balance -= _amount;
        unchecked {
            balanceBookEntry.claimableWithdrawals -= _amount;
        }
        _token.safeTransfer(msg.sender, _amount);

        emit FeeWithdrawalClaimed(_teamId, _token, _amount);
    }

    /**
     * @notice Advances fee collection cycle to allow teams to withdraw their funds
     * in case of prolonged inactivity by the fee collectors.
     * @dev Requirements:
     * - should be called at least FEE_COLLECTION_INACTIVITY_LIMIT time after lastFeeCollectionTime
     */
    function advanceFeeCollectionCycle() external {
        // Check that at least FEE_COLLECTION_INACTIVITY_LIMIT time has elapsed since last fee collection.
        require(
            block.timestamp > lastFeeCollectionTime + FEE_COLLECTION_INACTIVITY_LIMIT,
            "FeeManager::advanceFeeCollectionCycle: Time limit not reached yet."
        );

        feeCollectionCycle++;
        emit FeeCollectionComplete(feeCollectionCycle);
    }

    /**
     * @notice Gets balance for team-token.
     * @dev This function must return synced balance for team-token.
     * Requirements
     * - should be called for a valid team
     * @param _teamId Team identifier.
     * @param _token Token.
     * @return Balance for team-token.
     */
    function getBalance(string calldata _teamId, IERC20Upgradeable _token)
        external
        view
        isValidTeam(_teamId)
        returns (BalanceReport memory)
    {
        BalanceBookEntry memory entry = _getBalance(_teamId, _token);

        return
            BalanceReport({
                balance: entry.balance,
                claimableWithdrawals: entry.claimableWithdrawals,
                unclaimableWithdrawals: entry.unclaimableWithdrawals,
                collectableBalance: entry.balance - entry.claimableWithdrawals,
                requestableBalance: entry.balance -
                    entry.claimableWithdrawals -
                    entry.unclaimableWithdrawals
            });
    }

    /**
     * @notice Gets balances for team-token pairs.
     * Generates all combinations from provided teams and tokens and returns
     * balances for these pairs. Returned balances are organized as a 2D array,
     * with the outer index going over teams in _teamIds, and inner index going
     * over tokens in _tokens.
     * Example:
     * - calling with 1 team and 2 tokens will return [[{...}, {...}]]
     * - calling with 2 teams and 1 token will return [[{...}], [{...}]]
     * @dev This function must return synced balance for each team-token pair.
     * Requirements:
     * - should be called for valid teams
     * @param _teamIds Team identifiers.
     * @param _tokens Tokens.
     * @return Balances for team-token pairs.
     */
    function getBalances(string[] calldata _teamIds, IERC20Upgradeable[] calldata _tokens)
        external
        view
        returns (BalanceReport[][] memory)
    {
        BalanceReport[][] memory reports = new BalanceReport[][](_teamIds.length);

        // Loop over teams.
        for (uint256 i = 0; i < _teamIds.length; i++) {
            // Check if team is valid.
            _isValidTeam(_teamIds[i]);

            reports[i] = new BalanceReport[](_tokens.length);

            // Loop over tokens.
            for (uint256 j = 0; j < _tokens.length; j++) {
                // Get balance book entry for team-token.
                BalanceBookEntry memory entry = _getBalance(_teamIds[i], _tokens[j]);
                reports[i][j] = BalanceReport({
                    balance: entry.balance,
                    claimableWithdrawals: entry.claimableWithdrawals,
                    unclaimableWithdrawals: entry.unclaimableWithdrawals,
                    collectableBalance: entry.balance - entry.claimableWithdrawals,
                    requestableBalance: entry.balance -
                        entry.claimableWithdrawals -
                        entry.unclaimableWithdrawals
                });
            }
        }

        return reports;
    }

    /**
     * @dev Gets synced balance for team-token.
     * @param _teamId Team identifier.
     * @param _token Token.
     * @return Balance for team-token.
     */
    function _getBalance(string calldata _teamId, IERC20Upgradeable _token)
        private
        view
        returns (BalanceBookEntry memory)
    {
        BalanceBookEntry memory balanceBookEntry = _balanceBook[_teamId][_token];

        // Need to sync if it was not synced within current fee collection cycle.
        if (balanceBookEntry.lastSynced < feeCollectionCycle) {
            // Transfer withdrawal requests to balance available for withdrawal claims.
            balanceBookEntry.claimableWithdrawals += balanceBookEntry
                .unclaimableWithdrawals;
            balanceBookEntry.unclaimableWithdrawals = 0;

            // Update sync info.
            balanceBookEntry.lastSynced = feeCollectionCycle;

            // Balance available for withdrawal claims cannot be larger than token balance.
            if (balanceBookEntry.claimableWithdrawals > balanceBookEntry.balance) {
                balanceBookEntry.claimableWithdrawals = balanceBookEntry.balance;
            }
        }

        return balanceBookEntry;
    }

    /**
     * @dev Syncs balance book.
     * @param _teamId Team identifier.
     * @param _token Token.
     */
    function _syncBalanceBook(string calldata _teamId, IERC20Upgradeable _token) private {
        // Sync if needed.
        if (_balanceBook[_teamId][_token].lastSynced < feeCollectionCycle) {
            _balanceBook[_teamId][_token] = _getBalance(_teamId, _token);
        }
    }

    /* ========== RESTRICTION FUNCTIONS ========== */

    /**
     * @notice Ensures that token is allowed.
     */
    function _isAllowedToken(IERC20Upgradeable _token) private view {
        require(
            allowedTokens[_token],
            "FeeManager::_isAllowedToken: Token must be allowed."
        );
    }

    /**
     * @notice Ensures that caller is fee collector.
     */
    function _onlyFeeCollector() private view {
        require(
            feeCollectors[msg.sender],
            "FeeManager::_onlyFeeCollector: Caller must be a fee collector."
        );
    }

    /**
     * @notice Ensures that caller is team owner.
     */
    function _onlyTeamOwner(string calldata _teamId) private view {
        require(
            teams[_teamId].owner == msg.sender,
            "FeeManager::_onlyTeamOwner: Caller must be a team owner."
        );
    }

    /**
     * @notice Ensures that team is valid.
     */
    function _isValidTeam(string calldata _teamId) private view {
        require(teams[_teamId].valid, "FeeManager::_isValidTeam: Team must be valid.");
    }

    /**
     * @notice Ensures that caller is allowed to withdraw for the team.
     */
    function _isAllowedToWithdraw(string calldata _teamId) private view {
        require(
            isAllowedToWithdrawForTeam(_teamId, msg.sender),
            "FeeManager::_isAllowedToWithdraw: User must be allowed to withdraw."
        );
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Throws if token is not allowed.
     */
    modifier isAllowedToken(IERC20Upgradeable _token) {
        _isAllowedToken(_token);
        _;
    }

    /**
     * @notice Throws if caller is not fee collector.
     */
    modifier onlyFeeCollector() {
        _onlyFeeCollector();
        _;
    }

    /**
     * @notice Syncs balance book entry for team-token.
     */
    modifier syncBalanceBook(string calldata _teamId, IERC20Upgradeable _token) {
        _syncBalanceBook(_teamId, _token);
        _;
    }

    /**
     * @notice Throws if caller is not team owner.
     */
    modifier onlyTeamOwner(string calldata _teamId) {
        _onlyTeamOwner(_teamId);
        _;
    }

    /**
     * @notice Throws if team is not valid.
     */
    modifier isValidTeam(string calldata _teamId) {
        _isValidTeam(_teamId);
        _;
    }

    /**
     * @notice Throws if caller is not allowed to withdraw for team.
     */
    modifier isAllowedToWithdraw(string calldata _teamId) {
        _isAllowedToWithdraw(_teamId);
        _;
    }
}

