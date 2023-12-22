// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {ERC4626} from "./ERC4626.sol";
import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {ShareMath} from "./ShareMath.sol";
import {Pausable} from "./Pausable.sol";

import {IAggregateVault} from "./IAggregateVault.sol";
import {GlobalACL, Auth} from "./Auth.sol";

/// @title TimelockBoost
/// @author Umami DAO
/// @notice ERC4626 implementation for boosted vault tokens
contract TimelockBoost is ERC4626, Pausable, GlobalACL {
    using SafeTransferLib for ERC20;

    // STORAGE
    // ------------------------------------------------------------------------------------------

    /// @dev maximum number of queued withdrawals at once
    uint256 constant LOCK_QUEUE_LIMIT = 5;
    /// @dev the zap contract to allow users to deposit in one action
    address public ZAP;

    struct QueuedWithdrawal {
        uint256 queuedTimestamp;
        uint256 underlyingAmount;
    }

    struct TokenLockState {
        uint256 withdrawDuration;
        uint256 activeWithdrawBalance;
    }

    /// @dev state of the locking contract
    TokenLockState public lockState;

    /// @dev account => uint
    mapping(address => uint8) public activeWithdrawals;

    /// @dev account => QueuedWithdrawal[]
    mapping(address => QueuedWithdrawal[LOCK_QUEUE_LIMIT]) public withdrawalQueue;

    // EVENTS
    // ------------------------------------------------------------------------------------------

    event Deposit(address indexed _asset, address _account, uint256 _amount);
    event WithdrawInitiated(address indexed _asset, address _account, uint256 _amount, uint256 _duration);
    event WithdrawComplete(address indexed _asset, address _account, uint256 _amount);

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _withdrawDuration,
        Auth _auth) 
        ERC4626(_asset, _name, _symbol) GlobalACL(_auth) {
            lockState.withdrawDuration = _withdrawDuration;
        }

    // DEPOSIT & WITHDRAW
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Deposit assets and mint corresponding shares for the receiver.
     * @param assets The amount of assets to be deposited.
     * @param receiver The address that will receive the shares.
     * @return shares The number of shares minted for the deposited assets.
     */
    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Mint a specified amount of shares and deposit the corresponding amount of assets to the receiver
     * @param shares The amount of shares to mint
     * @param receiver The address to receive the deposited assets
     * @return assets The amount of assets deposited for the minted shares
     */
    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Initiate a withdrawal of the specified amount of assets.
     * @param _assets The amount of assets to withdraw.
     * @return shares The number of shares burned for the withdrawn assets.
     */
    function initiateWithdraw(
        uint256 _assets
    ) external whenNotPaused returns (uint256 shares) {
        shares = convertToShares(_assets);
        _initiateWithdrawShares(shares, _assets);
    }

    /**
     * @notice Initiate a withdrawal of the specified amount of shares.
     * @param _shares The amount of shares to withdraw.
     * @return _assets The number of assets withdrawn for given shares.
     */
    function initiateRedeem(uint _shares) external whenNotPaused returns (uint _assets) {
        _assets = convertToAssets(_shares);
        _initiateWithdrawShares(_shares, _assets);
    }

    /**
     * @notice Claim all available withdrawals for the sender.
     * @param _receiver The address that will receive the withdrawn assets.
     * @return _totalWithdraw The total amount of assets withdrawn.
     */
    function claimWithdrawals(address _receiver) external whenNotPaused returns (uint256 _totalWithdraw) {
        require(activeWithdrawals[msg.sender] > 0, "TimelockBoost: !activeWithdrawals");
        QueuedWithdrawal[LOCK_QUEUE_LIMIT] storage accountWithdrawals = withdrawalQueue[msg.sender];
        uint withdrawAmount;
        for (uint i = 0; i < LOCK_QUEUE_LIMIT; i++) {
            if (accountWithdrawals[i].queuedTimestamp + lockState.withdrawDuration < block.timestamp && accountWithdrawals[i].queuedTimestamp != 0) {
                withdrawAmount = _removeWithdrawForAccount(msg.sender, i);
                _decrementActiveWithdraws(msg.sender, withdrawAmount);
                _totalWithdraw += withdrawAmount;
            }
        }
        if (_totalWithdraw > 0) {
            asset.safeTransfer(_receiver, _totalWithdraw);
        }
        emit WithdrawComplete(address(asset), msg.sender, _totalWithdraw);
    }

    /**
     * @notice Claim all available withdrawals for the sender. Only used for Zap
     * @param _receiver The address that will receive the withdrawn assets.
     * @return _totalWithdraw The total amount of assets withdrawn.
     */
    function claimWithdrawalsFor(address _account, address _receiver) external whenNotPaused onlyZap returns (uint256 _totalWithdraw) {
        require(activeWithdrawals[_account] > 0, "TimelockBoost: !activeWithdrawals");
        QueuedWithdrawal[LOCK_QUEUE_LIMIT] storage accountWithdrawals = withdrawalQueue[_account];
        uint withdrawAmount;
        for (uint i = 0; i < LOCK_QUEUE_LIMIT; i++) {
            if (accountWithdrawals[i].queuedTimestamp + lockState.withdrawDuration < block.timestamp && accountWithdrawals[i].queuedTimestamp != 0) {
                withdrawAmount = _removeWithdrawForAccount(_account, i);
                _decrementActiveWithdraws(_account, withdrawAmount);
                _totalWithdraw += withdrawAmount;
            }
        }
        if (_totalWithdraw > 0) {
            asset.safeTransfer(_receiver, _totalWithdraw);
        }
        emit WithdrawComplete(address(asset), _account, _totalWithdraw);
    }


    // MATH
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Get the total assets
     */
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this)) - lockState.activeWithdrawBalance;
    }

    /**
     * @notice Calculate the current price per share (PPS) of the token.
     * @return pricePerShare The current price per share.
     */
    function pps() public view returns (uint256 pricePerShare) {
        uint256 supply = totalSupply; 
        return supply == 0 ? 10 ** decimals : (totalAssets() * 10 ** decimals) / supply;
    }

    /**
     * @notice Convert a specified amount of assets to shares
     * @param _assets The amount of assets to convert
     * @return - The amount of shares corresponding to the given assets
     */
    function convertToShares(uint256 _assets) public view override returns (uint256) {
        uint256 supply = totalSupply; 
        return supply == 0 ? _assets : ShareMath.assetToShares(_assets, pps(), decimals);
    }

    /**
     * @notice Convert a specified amount of shares to assets
     * @param _shares The amount of shares to convert
     * @return - The amount of assets corresponding to the given shares
     */
    function convertToAssets(uint256 _shares) public view override returns (uint256) {
        uint256 supply = totalSupply; 
        return supply == 0 ? _shares : ShareMath.sharesToAsset(_shares, pps(), decimals);
    }

    /**
     * @notice Preview the amount of shares for a given deposit amount
     * @param _assets The amount of assets to deposit
     * @return - The amount of shares for the given deposit amount
     */
    function previewDeposit(uint256 _assets) public view override returns (uint256) {
        return convertToShares(_assets);
    }

    /**
     * @notice Preview the amount of assets for a given mint amount
     * @param _shares The amount of shares to mint
     * @return _mintAmount The amount of assets for the given mint amount
     */
    function previewMint(uint256 _shares) public view override returns (uint256 _mintAmount) {
        uint256 supply = totalSupply; 
        _mintAmount = supply == 0 ? _shares : ShareMath.sharesToAsset(_shares, pps(), decimals);
    }

    /**
     * @notice Preview the amount of shares for a given withdrawal amount
     * @param _assets The amount of assets to withdraw
     * @return _withdrawAmount The amount of shares for the given withdrawal amount
     */
    function previewWithdraw(uint256 _assets) public view override returns (uint256 _withdrawAmount) {
        uint256 supply = totalSupply; 
        _withdrawAmount = supply == 0 ? _assets : ShareMath.assetToShares(_assets, pps(), decimals);
    }

    /**
     * @notice Returns an array of withdrawal requests for an account
     * @param _account The account
     * @return _array An array of withdrawal requests
     */
    function withdrawRequests(address _account) public view returns (QueuedWithdrawal[LOCK_QUEUE_LIMIT] memory) {
        QueuedWithdrawal[LOCK_QUEUE_LIMIT] memory accountWithdrawals = withdrawalQueue[_account];
        return accountWithdrawals;
    }

    /**
     * @notice Returns a struct for the locked state. To be used by contracts.
     * @return state Locked state struct
     */
    function getLockState() external view returns (TokenLockState memory state) {
        return lockState;
    }

    /**
     * @notice Returns a underlying token balance for a user
     * @return _underlyingBalance The users underlying balance
     */
    function underlyingBalance(address _account) external view returns (uint256 _underlyingBalance) {
        return convertToAssets(balanceOf[_account]);
    }


    // DEPOSIT & WITHDRAW LIMIT
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Get the maximum deposit amount for an address
     * @dev _address The address to check the maximum deposit amount for
     * @dev returns the maximum deposit amount for the given address
     */
    function maxDeposit(address) public view override returns (uint256) {
        return asset.totalSupply();
    }

    /**
     * @notice Get the maximum mint amount for an address
     */
    function maxMint(address) public view override returns (uint256) {
        return convertToShares(asset.totalSupply());
    }

    /**
     * @notice Get the maximum withdrawal amount for an address
     * @param owner The address to check the maximum withdrawal amount for
     * @return The maximum withdrawal amount for the given address
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        return convertToAssets(balanceOf[owner]);
    }


    // INTERNAL
    // ------------------------------------------------------------------------------------------

    function _initiateWithdrawShares(uint _shares, uint _assets) internal {
        require(activeWithdrawals[msg.sender] < LOCK_QUEUE_LIMIT, "TimelockBoost: > LOCK_QUEUE_LIMIT");

        _incrementActiveWithdraws(msg.sender, _assets);

        _addWithdrawForAccount(msg.sender, _assets);

        _burn(msg.sender, _shares);

        emit WithdrawInitiated(address(asset), msg.sender, _assets, lockState.withdrawDuration);
    }

    /**
     * @notice Increment the active withdrawal count and balance for the specified account.
     * @param _account The address of the account.
     * @param _assets The amount of assets to increment the active withdrawal balance.
     */
    function _incrementActiveWithdraws(address _account, uint256 _assets) internal {
        lockState.activeWithdrawBalance += _assets;
        activeWithdrawals[_account] += 1;
        require(activeWithdrawals[_account] <= LOCK_QUEUE_LIMIT, "TimelockBoost: !activeWithdrawalsLength");
    }

    /**
     * @notice Decrement the active withdrawal count and balance for the specified account.
     * @param _account The address of the account.
     * @param _assets The amount of assets to decrement the active withdrawal balance.
     */
    function _decrementActiveWithdraws(address _account, uint256 _assets) internal {
        lockState.activeWithdrawBalance -= _assets;
        activeWithdrawals[_account] -= 1;
    }

    /**
     * @notice Add a new withdrawal for the specified account.
     * @param _account The address of the account.
     * @param _assets The amount of assets to be added to the withdrawal queue.
     */
    function _addWithdrawForAccount(address _account, uint256 _assets) internal {
        QueuedWithdrawal[LOCK_QUEUE_LIMIT] storage accountWithdrawals = withdrawalQueue[_account];
        for (uint i = 0; i < LOCK_QUEUE_LIMIT; i++) {
            if (accountWithdrawals[i].queuedTimestamp == 0) {
                accountWithdrawals[i].queuedTimestamp = block.timestamp;
                accountWithdrawals[i].underlyingAmount = _assets;
                return;
            }
        }
    }

    /**
     * @notice Remove a withdrawal from the queue for the specified account.
     * @param _account The address of the account.
     * @param _index The index of the withdrawal to be removed.
     * @return underlyingAmount The amount of assets that were associated with the removed withdrawal.
     */
    function _removeWithdrawForAccount(address _account, uint256 _index) internal returns (uint256 underlyingAmount) {
        QueuedWithdrawal[LOCK_QUEUE_LIMIT] storage accountWithdrawals = withdrawalQueue[_account];
        require(accountWithdrawals[_index].queuedTimestamp + lockState.withdrawDuration < block.timestamp, "TimelockBoost: !withdrawalDuration");
        underlyingAmount = accountWithdrawals[_index].underlyingAmount;
        delete accountWithdrawals[_index];
    }

    // CONFIG
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Set the Zap contract address.
     * @dev Can only be called by configurator.
     * @param _zap The address of the Zap contract.
     */
    function setZap(address _zap) external onlyConfigurator {
        require(_zap != address(0), "TimelockBoost: ZAP set");
        ZAP = _zap;
    }

    /**
     * @notice Set the withdrawal duration for the contract.
     * @param _withdrawalDuration The new withdrawal duration in seconds.
     */
    function setWithdrawalDuration(uint256 _withdrawalDuration) external onlyConfigurator {
        lockState.withdrawDuration = _withdrawalDuration;
    }

    /**
     * @notice Pause deposit and withdrawal functionalities of the contract.
     */
    function pauseDepositWithdraw() external onlyConfigurator {
        _pause();
    }

    /**
     * @notice Pause deposit and withdrawal functionalities of the contract.
     */
    function unpauseDepositWithdraw() external onlyConfigurator {
        _unpause();
    }

    // MODIFIERS
    // ------------------------------------------------------------------------------------------

    /**
     * @dev Modifier to ensure that the caller is the Zap contract.
     */
    modifier onlyZap() {
        require(msg.sender == ZAP, "TimelockBoost: !ZAP");
        _;
    }

}

