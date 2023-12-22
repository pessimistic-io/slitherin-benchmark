// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./ILockBox.sol";
import "./TokenValidator.sol";
import "./IERC20.sol";
// For debugging only
//

/**
 * @title Lock Box
 * @author Deepp Dev Team
 * @notice Simple contract for storing tokens in a locked state.
 * @notice This is a sub contract for the BookieMain app.
 * @notice Its keeps a list of locked tokens and can own the locked tokens.
 * @notice TokenValidator is Accesshandler, Accesshandler is Initializable.
 */
contract LockBox is ILockBox, TokenValidator {
    // owner => token => amount
    mapping(address => mapping(address => uint256)) private lockedTokens;

    /**
     * Event that fires when tokens are locked.
     * @param owner is the address got the tokens locked.
     * @param token is the token contract address
     * @param lockedAmount is the amount locked.
     */
    event TokensLocked(
        address indexed owner,
        address indexed token,
        uint256 lockedAmount
    );

    /**
     * Event that fires when tokens are unlocked.
     * @param owner is the address got the tokens unlocked.
     * @param token is the token contract address
     * @param unlockedAmount is the amount unlocked.
     */
    event TokensUnlocked(
        address indexed owner,
        address indexed token,
        uint256 unlockedAmount
    );

    /**
     * Error for token approve failure,
     * although balance should always be available.
     * @param owner is the address that holds the tokens.
     * @param target is the address to receive the allowance.
     * @param token is the token contract address.
     * @param amount is the requested amount to approve.
     */
    error TokenApproveFailed
    (
        address owner,
        address target,
        address token,
        uint256 amount
    );

    /**
     * Error for token unlock failure,
     * although balance should always be available.
     * Needed `required` but only `available` available.
     * @param owner is the address that want to unlock tokens.
     * @param token is the token contract address.
     * @param available balance available.
     * @param required requested amount to unlock.
     */
    error InsufficientLockedTokens
    (
        address owner,
        address token,
        uint256 available,
        uint256 required
    );

    /**
     * @notice Default constructor.
     */
    constructor() {}

    /**
     * @notice Init function to call if this is deployed instead of extended.
     */
    function initBox() external notInitialized onlyRole(DEFAULT_ADMIN_ROLE) {
        _init();
    }

    /**
     * @notice Increases the users locked amount for a token.
     * @param owner The owner to update.
     * @param token The token type to lock in box.
     * @param amount The amount to add.
     */
    function lockAmount(
        address owner,
        address token,
        uint256 amount
    ) external override onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        _lock(owner, token, amount);
    }

    /**
     * @notice Decreases the users locked amount.
     * @param owner The owner to update.
     * @param token The token type to unlock.
     * @param amount The amount to unlock.
     */
    function unlockAmount(
        address owner,
        address token,
        uint256 amount
    ) external override onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        _unlock(owner, token, amount);
    }

    /**
     * @notice Decreases an owners locked amount and sets allowance to other.
     *         This assumes tokens are owned by the box and sets allowance.
     * @param owner The owner to update.
     * @param to The receiver of the token allowance.
     * @param token The token type to unlock.
     * @param amount The amount to unlock and allow.
     */
    function unlockAmountTo(
        address owner,
        address to,
        address token,
        uint256 amount
    ) external override onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        // We increase the allowance instead of setting it fixed,
        // although allowances for the box should be spend immediately.
        uint256 allowance = IERC20(token).allowance(address(this), to);
        allowance += amount;
        _unlock(owner, token, amount);

        bool success = IERC20(token).approve(to, allowance);
        if (!success) {
            revert TokenApproveFailed({
                owner: owner,
                target: to,
                token: token,
                amount: amount
            });
        }
    }

    /**
     * @notice Gets the users locked amount for a token.
     * @param owner The owner of the balance.
     * @param token The token type.
     * @return uint256 The amount currently locked.
     */
    function getLockedAmount(
        address owner,
        address token
    ) external view override returns (uint256) {
        return lockedTokens[owner][token];
    }

    /**
     * @notice Checks if user has a locked amount for a token.
     * @param owner The owner of the balance.
     * @param token The token type.
     * @param amount The amount to check.
     * @return bool True if the amount is locked, false if not.
     */
    function hasLockedAmount(
        address owner,
        address token,
        uint256 amount
    ) external view override returns (bool) {
        return lockedTokens[owner][token] >= amount;
    }

    /**
     * @notice Init function that initializes the Accesshandler.
     */
    function _init() internal {
        BaseInitializer.initialize();
    }

    /**
     * @notice Increases the users locked amount for a token.
     * @param owner The owner to update.
     * @param token The token type to lock in box.
     * @param amount The amount to add.
     */
    function _lock(
        address owner,
        address token,
        uint256 amount
    ) internal {
        lockedTokens[owner][token] += amount;
        emit TokensLocked(owner, token, amount);
    }

    /**
     * @notice Decreases the users locked amount.
     * @param owner The owner to update.
     * @param token The token type to unlock.
     * @param amount The amount to unlock.
     * @return bool True if the unlock succeeded, false if not.
     */
    function _unlock(
        address owner,
        address token,
        uint256 amount
    ) internal returns (bool) {
        if (amount == 0)
            return false;
        if (amount > lockedTokens[owner][token]) {
            revert InsufficientLockedTokens({
                owner: owner,
                token: token,
                available: lockedTokens[owner][token],
                required: amount
            });
        }
        lockedTokens[owner][token] -= amount;
        emit TokensUnlocked(owner, token, amount);
        return true;
    }
}

