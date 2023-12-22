// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeTransferLib, ERC20} from "./SafeTransferLib.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
import {SafeMath} from "./SafeMath.sol";

import "./IRewardsV2.sol";
import {IxGMBLToken} from "./IxGMBLToken.sol";
import {IxGMBLTokenUsage} from "./IxGMBLTokenUsage.sol";

import {Kernel, Module, Keycode} from "./Kernel.sol";

/*
 * This contract is used to distribute Rewards to users that allocated xGMBL here
 *
 * Rewards can be distributed in the form of one or more tokens
 * They are mainly managed to be received from the FeeManager contract, but other sources can be added (dev wallet for instance)
 *
 * The freshly received Rewards are stored in a pending slot
 *
 * The content of this pending slot will be progressively transferred over time into a distribution slot
 * This distribution slot is the source of the Rewards distribution to xGMBL allocators during the current cycle
 *
 * This transfer from the pending slot to the distribution slot is based on cycleRewardsPercent and CYCLE_PERIOD_SECONDS
 *
 */
contract REWRDV2 is ReentrancyGuard, Module, IxGMBLTokenUsage, IRewardsV2 {
    using SafeTransferLib for ERC20;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserInfo {
        uint256 pendingRewards;
        uint256 rewardDebt;
    }

    /// @dev token => user => UserInfo
    mapping(address => mapping(address => UserInfo)) public users;

    struct RewardsInfo {
        uint256 currentDistributionAmount; // total amount to distribute during the current cycle
        uint256 currentCycleDistributedAmount; // amount already distributed for the current cycle (times 1e2)
        uint256 pendingAmount; // total amount in the pending slot, not distributed yet
        uint256 distributedAmount; // total amount that has been distributed since initialization
        uint256 accRewardsPerShare; // accumulated rewards per share (times 1e18)
        uint256 lastUpdateTime; // last time the rewards distribution occurred
        uint256 cycleRewardsPercent; // fixed part of the pending rewards to assign to currentDistributionAmount on every cycle
        uint256 autoLockPercent; // percent of pendingRewards to convertTo xGBML and re-allocate for this usage
        bool distributionDisabled; // deactivate a token distribution (for temporary rewards)
    }

    /// @dev token => RewardsInfo global rewards info for a token
    mapping(address => RewardsInfo) public rewardsInfo;

    /// @dev actively distributed tokens
    EnumerableSet.AddressSet private _distributedTokens;
    uint256 public constant MAX_DISTRIBUTED_TOKENS = 10;

    /// @dev xGMBLToken contract
    address public immutable xGMBLToken;

    /// @dev User's xGMBL allocation
    mapping(address => uint256) public usersAllocation;

    /// @dev Contract's total xGMBL allocation
    uint256 public totalAllocation;

    /// @dev minimum cycle rewards pct can be set to to avoid rounding errors
    uint256 public constant MIN_CYCLE_REWARDS_PERCENT = 1; // 0.01%

    /// @dev default cycle rewards pct
    uint256 public constant DEFAULT_CYCLE_REWARDS_PERCENT = 100; // 1%

    /// @dev maximum cycle rewards pct mathematically allowable
    uint256 public constant MAX_CYCLE_REWARDS_PERCENT = 10000; // 100%

    // Rewards will be added to the currentDistributionAmount on each new cycle
    uint256 internal _cycleDurationSeconds = 7 days;
    uint256 public currentCycleStartTime;

    constructor(
        address xGMBLToken_,
        uint256 startTime_,
        Kernel kernel_
    ) Module(kernel_) {
        if (xGMBLToken_ == address(0)) revert REWRD_ZeroAddress();
        xGMBLToken = xGMBLToken_;
        currentCycleStartTime = startTime_;
    }

    /********************************************/
    /****************** ERRORS ******************/
    /********************************************/

    error REWRD_ZeroAddress();
    error REWRD_DistributedTokenIndexExists();
    error REWRD_DistributedTokenDoesNotExist();
    error REWRD_CallerNotXGMBL();
    error REWRD_HarvestRewardsInvalidToken();
    error REWRD_EmergencyWithdraw_TokenBalanceZero();
    error REWRD_TooManyDsitributedTokens();
    error REWRD_RewardsPercentOutOfRange();
    error REWRD_CannotRemoveDistributedToken();
    error REWRD_DistributedTokenAlreadyEnabled();
    error REWRD_DistributedTokenAlreadyDisabled();

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event UserUpdated(
        address indexed user,
        uint256 previousBalance,
        uint256 newBalance
    );
    event RewardsCollected(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event CycleRewardsPercentUpdated(
        address indexed token,
        uint256 previousValue,
        uint256 newValue
    );
    event RewardsAddedToPending(address indexed token, uint256 amount);
    event DistributedTokenDisabled(address indexed token);
    event DistributedTokenRemoved(address indexed token);
    event DistributedTokenEnabled(address indexed token);

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    /// @dev Checks if an index exists
    modifier validateDistributedTokensIndex(uint256 index) {
        if (index >= _distributedTokens.length())
            revert REWRD_DistributedTokenIndexExists();
        _;
    }

    /// @dev Checks if token exists
    modifier validateDistributedToken(address token) {
        if (!_distributedTokens.contains(token))
            revert REWRD_DistributedTokenDoesNotExist();
        _;
    }

    /// @dev Checks if caller is the xGMBLToken contract
    modifier xGMBLTokenOnly() {
        if (msg.sender != xGMBLToken) revert REWRD_CallerNotXGMBL();
        _;
    }

    /*******************************************/
    /****************** VIEWS ******************/
    /*******************************************/

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return Keycode.wrap("RWRDB");
    }

    /// @notice length of rewards dsitribution cycles in seconds
    function cycleDurationSeconds() external view returns (uint256) {
        return _cycleDurationSeconds;
    }

    /// @notice  Returns the number of Rewards tokens
    function distributedTokensLength()
        external
        view
        override
        returns (uint256)
    {
        return _distributedTokens.length();
    }

    /// @notice Returns rewards token address from given `index`
    function distributedToken(
        uint256 index
    )
        external
        view
        override
        validateDistributedTokensIndex(index)
        returns (address)
    {
        return address(_distributedTokens.at(index));
    }

    /// @notice Returns true if given token is a rewards `token`
    function isDistributedToken(
        address token
    ) external view override returns (bool) {
        return _distributedTokens.contains(token);
    }

    /// @notice Returns time at which the next cycle will start
    function nextCycleStartTime() public view returns (uint256) {
        return currentCycleStartTime + _cycleDurationSeconds;
    }

    /// @notice Returns `userAddress`'s unclaimed rewards of a given `token`
    function pendingRewardsAmount(
        address token,
        address userAddress
    ) external view returns (uint256) {
        if (totalAllocation == 0) {
            return 0;
        }

        RewardsInfo storage RewardsInfo_ = rewardsInfo[token];

        uint256 accRewardsPerShare = RewardsInfo_.accRewardsPerShare;
        uint256 lastUpdateTime = RewardsInfo_.lastUpdateTime;
        uint256 rewardAmountPerSecond_ = _RewardsAmountPerSecond(token);

        // check if the current cycle has changed since last update
        if (_currentBlockTimestamp() > nextCycleStartTime()) {
            accRewardsPerShare = accRewardsPerShare.add(
                (nextCycleStartTime().sub(lastUpdateTime))
                    .mul(rewardAmountPerSecond_)
                    .mul(1e16)
                    .div(totalAllocation)
            );

            lastUpdateTime = nextCycleStartTime();

            // div cycle rewards pct and cycle duration first
            rewardAmountPerSecond_ = RewardsInfo_
                .pendingAmount
                .mul(RewardsInfo_.cycleRewardsPercent)
                .div(100)
                .div(_cycleDurationSeconds);
        }

        // get pending rewards from current cycle
        accRewardsPerShare = accRewardsPerShare.add(
            (_currentBlockTimestamp().sub(lastUpdateTime))
                .mul(rewardAmountPerSecond_)
                .mul(1e16)
                .div(totalAllocation)
        );

        return
            usersAllocation[userAddress]
                .mul(accRewardsPerShare)
                .div(1e18)
                .sub(users[token][userAddress].rewardDebt)
                .add(users[token][userAddress].pendingRewards);
    }

    /**************************************************/
    /**************** PUBLIC FUNCTIONS ****************/
    /**************************************************/

    /// @notice Updates the current cycle start time if previous cycle has ended
    function updateCurrentCycleStartTime() public {
        uint256 nextCycleStartTime_ = nextCycleStartTime();

        if (_currentBlockTimestamp() >= nextCycleStartTime_) {
            currentCycleStartTime = nextCycleStartTime_;
        }
    }

    /// @notice Updates rewards info for a given `token`
    /// @dev anyone can call this to "poke" the state, updating internal accounting
    function updateRewardsInfo(
        address token
    ) external validateDistributedToken(token) {
        _updateRewardsInfo(token);
    }

    /// @notice Updates rewards info for all active distribution tokens
    /// @dev Anyone can call this to "poke" the state, updating internal accounting
    function massUpdateRewardsInfo() external {
        uint256 length = _distributedTokens.length();
        for (uint256 index = 0; index < length; ++index) {
            _updateRewardsInfo(_distributedTokens.at(index));
        }
    }

    /// @notice Harvests caller's pending Rewards of a given `token`
    function harvestRewards(address account, address token) external nonReentrant permissioned {
        if (!_distributedTokens.contains(token)) {
            if (rewardsInfo[token].distributedAmount == 0)
                revert REWRD_HarvestRewardsInvalidToken();
        }

        _harvestRewards(account, token);
    }

    /// @notice Harvests all caller's pending Rewards
    function harvestAllRewards(address account) external nonReentrant permissioned {
        uint256 length = _distributedTokens.length();
        for (uint256 index = 0; index < length; ++index) {
            _harvestRewards(account, _distributedTokens.at(index));
        }
    }

    /**************************************************/
    /*************** OWNABLE FUNCTIONS ****************/
    /**************************************************/

    /**
     * @notice Allocates `userAddress`'s `amount` of xGMBL to this Rewards contract
     * @dev Can only be called by xGMBLToken contract, which is trusted to verify amounts
     *
     * data Unused - to conform to IxGMBLTokenUsage
     */
    function allocate(
        address userAddress,
        uint256 amount,
        bytes calldata /*data*/
    ) external override nonReentrant xGMBLTokenOnly {
        uint256 newUserAllocation = usersAllocation[userAddress] + amount;
        uint256 newTotalAllocation = totalAllocation + amount;

        _updateUser(userAddress, newUserAllocation, newTotalAllocation);
    }

    /**
     * @notice Deallocates `userAddress`'s `amount` of xGMBL allocation from this Rewards contract
     * @dev Can only be called by xGMBLToken contract, which is trusted to verify amounts
     *
     * data Unused - to conform to IxGMBLTokenUsage
     */
    function deallocate(
        address userAddress,
        uint256 amount,
        bytes calldata /*data*/
    ) external override nonReentrant xGMBLTokenOnly {
        uint256 newUserAllocation = usersAllocation[userAddress] - amount;
        uint256 newTotalAllocation = totalAllocation - amount;

        _updateUser(userAddress, newUserAllocation, newTotalAllocation);
    }

    /// @notice Enables a given `token` to be distributed as rewards
    /// @dev Effective from the next cycle
    function enableDistributedToken(address token) external permissioned {
        RewardsInfo storage RewardsInfo_ = rewardsInfo[token];
        if (
            RewardsInfo_.lastUpdateTime > 0 &&
            !RewardsInfo_.distributionDisabled
        ) revert REWRD_DistributedTokenAlreadyEnabled();

        if (_distributedTokens.length() >= MAX_DISTRIBUTED_TOKENS)
            revert REWRD_TooManyDsitributedTokens();

        // initialize lastUpdateTime if never set before
        if (RewardsInfo_.lastUpdateTime == 0) {
            RewardsInfo_.lastUpdateTime = _currentBlockTimestamp();
        }
        // initialize cycleRewardsPercent to the minimum if never set before
        if (RewardsInfo_.cycleRewardsPercent == 0) {
            RewardsInfo_.cycleRewardsPercent = DEFAULT_CYCLE_REWARDS_PERCENT;
        }
        RewardsInfo_.distributionDisabled = false;
        _distributedTokens.add(token);
        emit DistributedTokenEnabled(token);
    }

    /// @notice Disables distribution of a given `token` as rewards
    /// @dev Effective from the next cycle
    function disableDistributedToken(address token) external permissioned {
        RewardsInfo storage RewardsInfo_ = rewardsInfo[token];

        if (
            RewardsInfo_.lastUpdateTime == 0 ||
            RewardsInfo_.distributionDisabled
        ) revert REWRD_DistributedTokenAlreadyDisabled();

        RewardsInfo_.distributionDisabled = true;
        emit DistributedTokenDisabled(token);
    }

    /// @notice Updates the `percent`-age of pending rewards `token` that will be distributed during the next cycle
    /// @dev Must be a value between MIN_CYCLE_REWARDS_PERCENT and MAX_CYCLE_REWARDS_PERCENT bps (1-10000)
    function updateCycleRewardsPercent(
        address token,
        uint256 percent
    ) external permissioned {
        if (
            percent > MAX_CYCLE_REWARDS_PERCENT ||
            percent < MIN_CYCLE_REWARDS_PERCENT
        ) revert REWRD_RewardsPercentOutOfRange();

        RewardsInfo storage RewardsInfo_ = rewardsInfo[token];
        uint256 previousPercent = RewardsInfo_.cycleRewardsPercent;
        RewardsInfo_.cycleRewardsPercent = percent;

        emit CycleRewardsPercentUpdated(
            token,
            previousPercent,
            RewardsInfo_.cycleRewardsPercent
        );
    }

    function updateAutoLockPercent(
        address token,
        uint256 percent
    ) external permissioned validateDistributedToken(token) {
        if (percent > 10000) revert("With custom error here > 100%");

        RewardsInfo storage RewardsInfo_ = rewardsInfo[token];
        uint256 previousPercent = RewardsInfo_.autoLockPercent;
        RewardsInfo_.autoLockPercent = percent;

        // emit AutoLockPercentUpdated(token, previousPercent, percent);
    }


    /// @notice Remove an address `tokenToRemove` from _distributedTokens
    /// @dev Can only be valid for a disabled Rewards token and if the distribution has ended
    function removeTokenFromDistributedTokens(
        address tokenToRemove
    ) external permissioned {
        RewardsInfo storage _RewardsInfo = rewardsInfo[tokenToRemove];

        if (
            !_RewardsInfo.distributionDisabled ||
            _RewardsInfo.currentDistributionAmount > 0
        ) revert REWRD_CannotRemoveDistributedToken();

        _distributedTokens.remove(tokenToRemove);
        emit DistributedTokenRemoved(tokenToRemove);
    }

    /// @notice Transfers the given amount of `token` from `distributor` to pendingAmount on behalf of `distributor`
    function addRewardsToPending(
        ERC20 token,
        address distributor,
        uint256 amount
    ) external override nonReentrant permissioned {
        uint256 prevTokenBalance = token.balanceOf(address(this));
        RewardsInfo storage RewardsInfo_ = rewardsInfo[address(token)];

        token.safeTransferFrom(distributor, address(this), amount);

        // handle tokens with transfer tax
        uint256 receivedAmount = token.balanceOf(address(this)) -
            prevTokenBalance;
        RewardsInfo_.pendingAmount += receivedAmount;

        emit RewardsAddedToPending(address(token), receivedAmount);
    }

    /// @notice Emergency withdraw `token`'s balance on the contract to `receiver`
    function emergencyWithdraw(
        ERC20 token,
        address receiver
    ) public nonReentrant permissioned {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) revert REWRD_EmergencyWithdraw_TokenBalanceZero();
        _safeTokenTransfer(token, receiver, balance);
    }

    /// @notice Emergency withdraw all reward tokens' balances on the contract to `receiver`
    function emergencyWithdrawAll(
        address receiver
    ) external nonReentrant permissioned {
        for (uint256 index = 0; index < _distributedTokens.length(); ++index) {
            emergencyWithdraw(ERC20(_distributedTokens.at(index)), receiver);
        }
    }

    /********************************************************/
    /****************** INTERNAL FUNCTIONS ******************/
    /********************************************************/

    /// @dev Returns the amount of Rewards token distributed every second (times 1e2)
    function _RewardsAmountPerSecond(
        address token
    ) internal view returns (uint256) {
        if (!_distributedTokens.contains(token)) return 0;
        return
            rewardsInfo[token].currentDistributionAmount.mul(1e2).div(
                _cycleDurationSeconds
            );
    }

    /// @dev Updates every user's rewards allocation for each distributed token
    function _updateRewardsInfo(address token) internal {
        uint256 currentBlockTimestamp = _currentBlockTimestamp();
        RewardsInfo storage RewardsInfo_ = rewardsInfo[token];

        updateCurrentCycleStartTime();

        uint256 lastUpdateTime = RewardsInfo_.lastUpdateTime;
        uint256 accRewardsPerShare = RewardsInfo_.accRewardsPerShare;

        if (currentBlockTimestamp <= lastUpdateTime) {
            return;
        }

        // if no xGMBL is allocated or initial distribution has not started yet
        if (
            totalAllocation == 0 ||
            currentBlockTimestamp < currentCycleStartTime
        ) {
            RewardsInfo_.lastUpdateTime = currentBlockTimestamp;
            return;
        }

        uint256 currentDistributionAmount = RewardsInfo_
            .currentDistributionAmount; // gas saving
        uint256 currentCycleDistributedAmount = RewardsInfo_
            .currentCycleDistributedAmount; // gas saving

        // check if the current cycle has changed since last update
        if (lastUpdateTime < currentCycleStartTime) {
            // update accrewardPerShare for the end of the previous cycle
            accRewardsPerShare = accRewardsPerShare.add(
                (
                    currentDistributionAmount.mul(1e2).sub(
                        currentCycleDistributedAmount
                    )
                ).mul(1e16).div(totalAllocation)
            );

            // check if distribution is enabled
            if (!RewardsInfo_.distributionDisabled) {
                // transfer the token's cycleRewardsPercent part from the pending slot to the distribution slot
                RewardsInfo_.distributedAmount += currentDistributionAmount;

                uint256 pendingAmount = RewardsInfo_.pendingAmount;
                currentDistributionAmount = pendingAmount
                    .mul(RewardsInfo_.cycleRewardsPercent)
                    .div(10000);

                RewardsInfo_
                    .currentDistributionAmount = currentDistributionAmount;
                RewardsInfo_.pendingAmount =
                    pendingAmount -
                    currentDistributionAmount;
            } else {
                // stop the token's distribution on next cycle
                RewardsInfo_.distributedAmount += currentDistributionAmount;
                currentDistributionAmount = 0;
                RewardsInfo_.currentDistributionAmount = 0;
            }

            currentCycleDistributedAmount = 0;
            lastUpdateTime = currentCycleStartTime;
        }

        uint256 toDistribute = currentBlockTimestamp.sub(lastUpdateTime).mul(
            _RewardsAmountPerSecond(token)
        );

        // ensure that we can't distribute more than currentDistributionAmount (for instance w/ a > 24h service interruption)
        if (
            currentCycleDistributedAmount + toDistribute >
            currentDistributionAmount * 1e2
        ) {
            toDistribute = currentDistributionAmount.mul(1e2).sub(
                currentCycleDistributedAmount
            );
        }

        RewardsInfo_.currentCycleDistributedAmount =
            currentCycleDistributedAmount +
            toDistribute;
        RewardsInfo_.accRewardsPerShare = accRewardsPerShare.add(
            toDistribute.mul(1e16).div(totalAllocation)
        );
        RewardsInfo_.lastUpdateTime = currentBlockTimestamp;
    }

    /// @dev Updates "userAddress" user's and total allocations for each distributed token
    function _updateUser(
        address userAddress,
        uint256 newUserAllocation,
        uint256 newTotalAllocation
    ) internal {
        uint256 previousUserAllocation = usersAllocation[userAddress];

        // for each distributedToken
        uint256 length = _distributedTokens.length();

        for (uint256 index = 0; index < length; ++index) {
            address token = _distributedTokens.at(index);
            _updateRewardsInfo(token);

            UserInfo storage user = users[token][userAddress];
            uint256 accRewardsPerShare = rewardsInfo[token].accRewardsPerShare;

            uint256 pending = previousUserAllocation
                .mul(accRewardsPerShare)
                .div(1e18)
                .sub(user.rewardDebt);

            user.pendingRewards += pending;
            user.rewardDebt = newUserAllocation.mul(accRewardsPerShare).div(
                1e18
            );
        }

        usersAllocation[userAddress] = newUserAllocation;
        totalAllocation = newTotalAllocation;

        emit UserUpdated(
            userAddress,
            previousUserAllocation,
            newUserAllocation
        );
    }

    /// @dev Harvests msg.sender's pending Rewards of a given token
    function _harvestRewards(address account, address token) internal {
        _updateRewardsInfo(token);

        UserInfo storage user = users[token][account];
        uint256 accRewardsPerShare = rewardsInfo[token].accRewardsPerShare;

        uint256 userxGMBLAllocation = usersAllocation[account];

        uint256 pending = user.pendingRewards.add(
            userxGMBLAllocation.mul(accRewardsPerShare).div(1e18).sub(
                user.rewardDebt
            )
        );

        _safeTokenTransfer(ERC20(token), account, pending);
        // Re-stake current autoLock ratio of pending rewards
        if (token == IxGMBLToken(xGMBLToken).getGMBL()) {
            uint256 relock = pending
                .mul(rewardsInfo[token].autoLockPercent)
                .div(10000);

            if (relock > 0) {
                pending -= relock;

                IxGMBLToken(xGMBLToken).convertTo(relock, account);
                IxGMBLToken(xGMBLToken).allocateFromUsage(account, relock);
            }
        }

        user.pendingRewards = 0;
        user.rewardDebt = userxGMBLAllocation.mul(accRewardsPerShare).div(1e18);


        emit RewardsCollected(account, token, pending);
    }

    /// @dev Safe token transfer function, in case rounding error causes pool to not have enough tokens
    function _safeTokenTransfer(
        ERC20 token,
        address to,
        uint256 amount
    ) internal {
        if (amount > 0) {
            uint256 tokenBal = token.balanceOf(address(this));
            if (amount > tokenBal) {
                token.safeTransfer(to, tokenBal);
            } else {
                token.safeTransfer(to, amount);
            }
        }
    }

    /// @dev Utility function to get the current block timestamp
    function _currentBlockTimestamp() internal view virtual returns (uint256) {
        /* solhint-disable not-rely-on-time */
        return block.timestamp;
    }
}

