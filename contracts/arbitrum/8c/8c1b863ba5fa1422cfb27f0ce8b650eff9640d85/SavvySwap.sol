// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./Errors.sol";

import "./IAllowlist.sol";

import "./ISavvySwap.sol";
import "./ISavvySage.sol";

import "./FixedPointMath.sol";
import "./LiquidityMath.sol";
import "./SafeCast.sol";
import "./Tick.sol";
import "./TokenUtils.sol";
import "./Checker.sol";

/// @title SavvySwap
///
/// @notice A contract which facilitates the swap of synthetic tokens for their base token.
//  @notice This contract guarantees that synthetic tokens are swapped exactly 1:1 for the base token.
contract SavvySwap is
    ISavvySwap,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable
{
    using FixedPointMath for FixedPointMath.Number;
    using Tick for Tick.Cache;

    struct Account {
        // The total number of unswapped tokens that an account has deposited into the system
        uint256 unswappedBalance;
        // The total number of swapped tokens that an account has had credited
        uint256 swappedBalance;
        // The tick that the account has had their deposit associated in
        uint256 occupiedTick;
    }

    struct UpdateAccountParams {
        // The owner address whose account will be modified
        address owner;
        // The amount to change the account's unswapped balance by
        int256 unswappedDelta;
        // The amount to change the account's swapped balance by
        int256 swappedDelta;
    }

    struct SwapCache {
        // The total number of unswapped tokens that exist at the start of the swap call
        uint256 totalUnswapped;
        // The tick which has been satisfied up to at the start of the swap call
        uint256 satisfiedTick;
        // The head of the active ticks queue at the start of the swap call
        uint256 ticksHead;
    }

    struct SwapState {
        // The position in the buffer of current tick which is being examined
        uint256 examineTick;
        // The total number of unswapped tokens that currently exist in the system for the current distribution step
        uint256 totalUnswapped;
        // The tick which has been satisfied up to, inclusive
        uint256 satisfiedTick;
        // The amount of tokens to distribute for the current step
        uint256 distributeAmount;
        // The accumulated weight to write at the new tick after the swap is completed
        FixedPointMath.Number accumulatedWeight;
        // Reserved for the maximum weight of the current distribution step
        FixedPointMath.Number maximumWeight;
        // Reserved for the dusted weight of the current distribution step
        FixedPointMath.Number dustedWeight;
    }

    struct UpdateAccountCache {
        // The total number of unswapped tokens that the account held at the start of the update call
        uint256 unswappedBalance;
        // The total number of swapped tokens that the account held at the start of the update call
        uint256 swappedBalance;
        // The tick that the account's deposit occupies at the start of the update call
        uint256 occupiedTick;
        // The total number of unswapped tokens that exist at the start of the update call
        uint256 totalUnswapped;
        // The current tick that is being written to
        uint256 currentTick;
    }

    struct UpdateAccountState {
        // The updated unswapped balance of the account being updated
        uint256 unswappedBalance;
        // The updated swapped balance of the account being updated
        uint256 swappedBalance;
        // The updated total unswapped balance
        uint256 totalUnswapped;
    }

    address public constant ZERO_ADDRESS = address(0);

    /// @dev The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN = keccak256("ADMIN");

    /// @dev The identitifer of the sentinel role
    bytes32 public constant SENTINEL = keccak256("SENTINEL");

    /// @inheritdoc ISavvySwap
    string public constant override version = "1.0.0";

    /// @dev the synthetic token to be savvy swapped
    address public override syntheticToken;

    /// @dev the base token to be received
    address public override baseToken;

    /// @dev The total amount of unswapped tokens which are held by all accounts.
    uint256 public totalUnswapped;

    /// @dev The total amount of tokens which are in the auxiliary buffer.
    uint256 public totalBuffered;

    /// @dev A mapping specifying all of the accounts.
    mapping(address => Account) private accounts;

    // @dev The tick buffer which stores all of the tick information along with the tick that is
    //      currently being written to. The "current" tick is the tick at the buffer write position.
    Tick.Cache private ticks;

    // The tick which has been satisfied up to, inclusive.
    uint256 private satisfiedTick;

    /// @dev contract pause state
    bool public isPaused;

    /// @dev the source of the swapped collateral
    address public buffer;

    /// @dev The address of the external allowlist contract.
    address public override allowlist;

    /// @dev The amount of decimal places needed to normalize collateral to debtToken
    uint256 public override conversionFactor;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _syntheticToken,
        address _baseToken,
        address _buffer,
        address _allowlist
    ) external initializer {
        __ReentrancyGuard_init_unchained();
        __AccessControl_init_unchained();

        _grantRole(ADMIN, msg.sender);
        _setRoleAdmin(ADMIN, ADMIN);
        _setRoleAdmin(SENTINEL, ADMIN);

        syntheticToken = _syntheticToken;
        baseToken = _baseToken;
        uint8 debtTokenDecimals = TokenUtils.expectDecimals(syntheticToken);
        uint8 baseTokenDecimals = TokenUtils.expectDecimals(baseToken);
        conversionFactor = 10 ** (debtTokenDecimals - baseTokenDecimals);
        buffer = _buffer;
        // Push a blank tick to function as a sentinel value in the active ticks queue.
        ticks.next();

        isPaused = false;
        allowlist = _allowlist;
    }

    /// @dev A modifier which checks if caller is an savvy.
    modifier onlySage() {
        require(msg.sender == buffer, "Unauthorized savvySage");
        _;
    }

    /// @dev A modifier which checks if caller is a sentinel or admin.
    modifier onlySentinelOrAdmin() {
        require(
            hasRole(SENTINEL, msg.sender) || hasRole(ADMIN, msg.sender),
            "Unauthorized sentinel or admin"
        );
        _;
    }

    /// @dev A modifier which checks if contract is a paused.
    modifier notPaused() {
        Checker.checkState(!isPaused, "paused");
        _;
    }

    function _onlyAdmin() internal view {
        require(hasRole(ADMIN, msg.sender), "Unauthorized admin");
    }

    function setCollateralSource(address _newCollateralSource) external {
        _onlyAdmin();
        buffer = _newCollateralSource;
    }

    function setPause(bool pauseState) external onlySentinelOrAdmin {
        isPaused = pauseState;
        emit Paused(isPaused);
    }

    /// @inheritdoc ISavvySwap
    function deposit(
        uint256 amount,
        address owner
    ) external override nonReentrant notPaused {
        _onlyAllowlisted();
        amount = TokenUtils.safeTransferFrom(
            syntheticToken,
            msg.sender,
            address(this),
            amount
        );
        _updateAccount(
            UpdateAccountParams({
                owner: owner,
                unswappedDelta: SafeCast.toInt256(amount),
                swappedDelta: 0
            })
        );
        emit Deposit(msg.sender, owner, amount);
    }

    /// @inheritdoc ISavvySwap
    function withdraw(
        uint256 amount,
        address recipient
    ) external override nonReentrant {
        _onlyAllowlisted();
        _updateAccount(
            UpdateAccountParams({
                owner: msg.sender,
                unswappedDelta: -SafeCast.toInt256(amount),
                swappedDelta: 0
            })
        );
        TokenUtils.safeTransfer(syntheticToken, recipient, amount);
        emit Withdraw(msg.sender, recipient, amount);
    }

    /// @inheritdoc ISavvySwap
    function claim(
        uint256 amount,
        address recipient
    ) external override nonReentrant {
        _onlyAllowlisted();

        uint256 debtAmount = _normalizeBaseTokensToDebt(amount);
        _updateAccount(
            UpdateAccountParams({
                owner: msg.sender,
                unswappedDelta: 0,
                swappedDelta: -SafeCast.toInt256(debtAmount)
            })
        );
        TokenUtils.safeBurn(syntheticToken, debtAmount);
        ISavvySage(buffer).withdraw(baseToken, amount, recipient);
        emit Claim(msg.sender, recipient, amount);
    }

    /// @inheritdoc ISavvySwap
    function swap(
        uint256 amount
    ) external override nonReentrant onlySage notPaused {
        uint256 normalizedAmount = _normalizeBaseTokensToDebt(amount);

        if (totalUnswapped == 0) {
            totalBuffered += normalizedAmount;
            emit Swap(msg.sender, amount);
            return;
        }

        // Push a storage reference to the current tick.
        Tick.Info storage current = ticks.current();

        SwapCache memory cache = SwapCache({
            totalUnswapped: totalUnswapped,
            satisfiedTick: satisfiedTick,
            ticksHead: ticks.head
        });

        SwapState memory state = SwapState({
            examineTick: cache.ticksHead,
            totalUnswapped: cache.totalUnswapped,
            satisfiedTick: cache.satisfiedTick,
            distributeAmount: normalizedAmount,
            accumulatedWeight: current.accumulatedWeight,
            maximumWeight: FixedPointMath.encode(0),
            dustedWeight: FixedPointMath.encode(0)
        });

        // Distribute the buffered tokens as part of the swap.
        state.distributeAmount += totalBuffered;
        totalBuffered = 0;

        // Push a storage reference to the next tick to write to.
        Tick.Info storage next = ticks.next();

        // Only iterate through the active ticks queue when it is not empty.
        while (state.examineTick != 0) {
            // Check if there is anything left to distribute.
            if (state.distributeAmount == 0) {
                break;
            }

            Tick.Info storage examineTickData = ticks.get(state.examineTick);

            // Add the weight for the distribution step to the accumulated weight.
            state.accumulatedWeight = state.accumulatedWeight.add(
                FixedPointMath.rational(
                    state.distributeAmount,
                    state.totalUnswapped
                )
            );

            // Clear the distribute amount.
            state.distributeAmount = 0;

            // Calculate the current maximum weight in the system.
            state.maximumWeight = state.accumulatedWeight.sub(
                examineTickData.accumulatedWeight
            );

            // Check if there exists at least one account which is completely satisfied..
            if (state.maximumWeight.n < FixedPointMath.ONE) {
                break;
            }

            // Calculate how much weight of the distributed weight is dust.
            state.dustedWeight = FixedPointMath.Number(
                state.maximumWeight.n - FixedPointMath.ONE
            );

            // Calculate how many tokens to distribute in the next step. These are tokens from any tokens which
            // were over allocated to accounts occupying the tick with the maximum weight.
            state.distributeAmount = LiquidityMath.calculateProduct(
                examineTickData.totalBalance,
                state.dustedWeight
            );

            // Remove the tokens which were completely swapped from the total unswapped balance.
            state.totalUnswapped -= examineTickData.totalBalance;

            // Write that all ticks up to and including the examined tick have been satisfied.
            state.satisfiedTick = state.examineTick;

            // Visit the next active tick. This is equivalent to popping the head of the active ticks queue.
            state.examineTick = examineTickData.next;
        }

        // Write the accumulated weight to the next tick.
        next.accumulatedWeight = state.accumulatedWeight;

        if (cache.totalUnswapped != state.totalUnswapped) {
            totalUnswapped = state.totalUnswapped;
        }

        if (cache.satisfiedTick != state.satisfiedTick) {
            satisfiedTick = state.satisfiedTick;
        }

        if (cache.ticksHead != state.examineTick) {
            ticks.head = state.examineTick;
        }

        if (state.distributeAmount > 0) {
            totalBuffered += state.distributeAmount;
        }

        emit Swap(msg.sender, amount);
    }

    /// @inheritdoc ISavvySwap
    function getUnswappedBalance(
        address owner
    ) external view override returns (uint256 unswappedBalance) {
        Account storage account = accounts[owner];

        if (account.occupiedTick <= satisfiedTick) {
            return 0;
        }

        unswappedBalance = account.unswappedBalance;

        uint256 swapped = LiquidityMath.calculateProduct(
            unswappedBalance,
            ticks.getWeight(account.occupiedTick, ticks.position)
        );

        unswappedBalance -= swapped;

        return unswappedBalance;
    }

    /// @inheritdoc ISavvySwap
    function getSwappedBalance(
        address owner
    ) external view override returns (uint256 swappedBalance) {
        return _getswappedBalance(owner);
    }

    function getClaimableBalance(
        address owner
    ) external view override returns (uint256 claimableBalance) {
        return _normalizeDebtTokensToUnderlying(_getswappedBalance(owner));
    }

    /// @dev Updates an account.
    ///
    /// @param params The call parameters.
    function _updateAccount(UpdateAccountParams memory params) internal {
        Account storage account = accounts[params.owner];

        UpdateAccountCache memory cache = UpdateAccountCache({
            unswappedBalance: account.unswappedBalance,
            swappedBalance: account.swappedBalance,
            occupiedTick: account.occupiedTick,
            totalUnswapped: totalUnswapped,
            currentTick: ticks.position
        });

        UpdateAccountState memory state = UpdateAccountState({
            unswappedBalance: cache.unswappedBalance,
            swappedBalance: cache.swappedBalance,
            totalUnswapped: cache.totalUnswapped
        });

        // Updating an account is broken down into five steps:
        // 1). Synchronize the account if it previously occupied a satisfied tick
        // 2). Update the account balances to account for swapped tokens, if any
        // 3). Apply the deltas to the account balances
        // 4). Update the previously occupied and/or current tick's liquidity
        // 5). Commit changes to the account and global state when needed

        // Step one:
        // ---------
        // Check if the tick that the account was occupying previously was satisfied. If it was, we acknowledge
        // that all of the tokens were swapped.
        if (state.unswappedBalance > 0 && satisfiedTick >= cache.occupiedTick) {
            state.unswappedBalance = 0;
            state.swappedBalance += cache.unswappedBalance;
        }

        // Step Two:
        // ---------
        // Calculate how many tokens were swapped since the last update.
        if (state.unswappedBalance > 0) {
            uint256 swapped = LiquidityMath.calculateProduct(
                state.unswappedBalance,
                ticks.getWeight(cache.occupiedTick, cache.currentTick)
            );

            state.totalUnswapped -= swapped;
            state.unswappedBalance -= swapped;
            state.swappedBalance += swapped;
        }

        // Step Three:
        // -----------
        // Apply the unswapped and swapped deltas to the state.
        state.totalUnswapped = LiquidityMath.addDelta(
            state.totalUnswapped,
            params.unswappedDelta
        );
        state.unswappedBalance = LiquidityMath.addDelta(
            state.unswappedBalance,
            params.unswappedDelta
        );
        state.swappedBalance = LiquidityMath.addDelta(
            state.swappedBalance,
            params.swappedDelta
        );

        // Step Four:
        // ----------
        // The following is a truth table relating various values which in combinations specify which logic branches
        // need to be executed in order to update liquidity in the previously occupied and/or current tick.
        //
        // Some states are not obtainable and are just discarded by setting all the branches to false.
        //
        // | P | C | M | Modify Liquidity | Add Liquidity | Subtract Liquidity |
        // |---|---|---|------------------|---------------|--------------------|
        // | F | F | F | F                | F             | F                  |
        // | F | F | T | F                | F             | F                  |
        // | F | T | F | F                | T             | F                  |
        // | F | T | T | F                | T             | F                  |
        // | T | F | F | F                | F             | T                  |
        // | T | F | T | F                | F             | T                  |
        // | T | T | F | T                | F             | F                  |
        // | T | T | T | F                | T             | T                  |
        //
        // | Branch             | Reduction |
        // |--------------------|-----------|
        // | Modify Liquidity   | PCM'      |
        // | Add Liquidity      | P'C + CM  |
        // | Subtract Liquidity | PC' + PM  |

        bool previouslyActive = cache.unswappedBalance > 0;
        bool currentlyActive = state.unswappedBalance > 0;
        bool migrate = cache.occupiedTick != cache.currentTick;

        bool modifyLiquidity = previouslyActive && currentlyActive && !migrate;

        if (modifyLiquidity) {
            Tick.Info storage tick = ticks.get(cache.occupiedTick);

            // Consolidate writes to save gas.
            uint256 totalBalance = tick.totalBalance;
            totalBalance -= cache.unswappedBalance;
            totalBalance += state.unswappedBalance;
            tick.totalBalance = totalBalance;
        } else {
            bool addLiquidity = (!previouslyActive && currentlyActive) ||
                (currentlyActive && migrate);
            bool subLiquidity = (previouslyActive && !currentlyActive) ||
                (previouslyActive && migrate);

            if (addLiquidity) {
                Tick.Info storage tick = ticks.get(cache.currentTick);

                if (tick.totalBalance == 0) {
                    ticks.addLast(cache.currentTick);
                }

                tick.totalBalance += state.unswappedBalance;
            }

            if (subLiquidity) {
                Tick.Info storage tick = ticks.get(cache.occupiedTick);
                tick.totalBalance -= cache.unswappedBalance;

                if (tick.totalBalance == 0) {
                    ticks.remove(cache.occupiedTick);
                }
            }
        }

        // Step Five:
        // ----------
        // Commit the changes to the account.
        if (cache.unswappedBalance != state.unswappedBalance) {
            account.unswappedBalance = state.unswappedBalance;
        }

        if (cache.swappedBalance != state.swappedBalance) {
            account.swappedBalance = state.swappedBalance;
        }

        if (cache.totalUnswapped != state.totalUnswapped) {
            totalUnswapped = state.totalUnswapped;
        }

        if (cache.occupiedTick != cache.currentTick) {
            account.occupiedTick = cache.currentTick;
        }
    }

    /// @dev Checks the allowlist for msg.sender.
    ///
    /// @notice Reverts if msg.sender is not in the allowlist.
    function _onlyAllowlisted() internal view {
        // Check if the message sender is an EOA. In the future, this potentially may break. It is important that
        // functions which rely on the allowlist not be explicitly vulnerable in the situation where this no longer
        // holds true.
        address sender = msg.sender;
        require(
            tx.origin == sender || IAllowlist(allowlist).isAllowed(sender),
            "Unauthorized collateral source"
        );
    }

    /// @dev Normalize `amount` of `baseToken` to a value which is comparable to units of the debt token.
    ///
    /// @param amount          The amount of the debt token.
    ///
    /// @return The normalized amount.
    function _normalizeBaseTokensToDebt(
        uint256 amount
    ) internal view returns (uint256) {
        return amount * conversionFactor;
    }

    /// @dev Normalize `amount` of the debt token to a value which is comparable to units of `baseToken`.
    ///
    /// @dev This operation will result in truncation of some of the least significant digits of `amount`. This
    ///      truncation amount will be the least significant N digits where N is the difference in decimals between
    ///      the debt token and the base token.
    ///
    /// @param amount          The amount of the debt token.
    ///
    /// @return The normalized amount.
    function _normalizeDebtTokensToUnderlying(
        uint256 amount
    ) internal view returns (uint256) {
        return amount / conversionFactor;
    }

    function _getswappedBalance(
        address owner
    ) internal view returns (uint256 swappedBalance) {
        Account storage account = accounts[owner];

        if (account.occupiedTick <= satisfiedTick) {
            swappedBalance = account.swappedBalance;
            swappedBalance += account.unswappedBalance;
            return swappedBalance;
        }

        swappedBalance = account.swappedBalance;

        uint256 swapped = LiquidityMath.calculateProduct(
            account.unswappedBalance,
            ticks.getWeight(account.occupiedTick, ticks.position)
        );

        swappedBalance += swapped;

        return swappedBalance;
    }

    uint256[100] private __gap;
}

