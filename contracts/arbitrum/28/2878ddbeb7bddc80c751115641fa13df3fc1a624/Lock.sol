// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;
pragma abicoder v2;

import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafeMath} from "./SafeMath.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

import {IMultiFeeDistribution, IFeeDistribution} from "./IMultiFeeDistribution.sol";
import {ILockerList} from "./ILockerList.sol";
import {LockedBalance, Balances, Reward, EarnedBalance} from "./LockedBalance.sol";
import {IWETH} from "./IWETH.sol";
import {console2} from "./console2.sol";
/// @title Multi Fee Distribution Contract
/// @author Gamma
/// @dev All function calls are currently implemented without side effects

contract MultiFeeDistribution is
    IMultiFeeDistribution,
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /********************** Constants ***********************/

    uint256 public basePenaltyPercentage; //  25%
    uint256 public timePenaltyFraction; //  65%
    uint256 public constant WHOLE = 100000; // 100%

    /********************** Contract Addresses ***********************/

    /// @notice Address of LP token
    address public override stakingToken;

    address public treasury;

    /// @notice weth address
    address public WETH;
    address public constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    /********************** Lock & Earn Info ***********************/

    // Private mappings for balance data
    mapping(address => Balances) private balances;
    mapping(address => LockedBalance[]) internal userLocks;

    /// @notice Total locked value
    uint256 public lockedSupply;

    /// @notice Total locked value in multipliers
    uint256 public lockedSupplyWithMultiplier;

    /********************** Reward Info ***********************/

    /// @notice Reward tokens being distributed
    address[] public rewardTokens;
    mapping(address => Reward) public rewardData;

    uint256[] internal lockPeriod;
    uint256[] internal rewardMultipliers;

    /// @notice user -> reward token -> amount; used to store reward amount
    mapping(address => mapping(address => uint256)) public rewards;
    mapping(address => mapping(address => uint256)) internal rewardPaid;
    mapping(address => mapping(address => uint256)) internal rewardDebt;
    mapping(address => mapping(address => uint256)) internal lastTimeClaim;
    mapping(address => uint256) public expiredWithdrawable;
    /********************** Other Info ***********************/

    /// @notice Authority infos
    mapping(address => bool) public guardians;
    mapping(address => bool) public keepers;
    mapping(address => bool) public override autoRelockDisabled;

    // Default lock index for relock
    mapping(address => uint256) public override defaultLockIndex;

    /// @notice Users list
    ILockerList public userlist;

    // to prevent unbounded lock length iteration during withdraw/clean

    /********************** Events ***********************/

    // event Staked(address indexed user, uint256 amount, bool locked);
    event Locked(
        address indexed user,
        uint256 amount,
        uint256 lockedBalance
    );
    event Withdrawn(
        address indexed user,
        uint256 receivedAmount,
        uint256 lockedBalance,
        uint256 penalty,
        uint256 burn
    );
    event RewardPaid(
        address indexed user,
        address indexed rewardToken,
        uint256 reward
    );
    event Recovered(address indexed token, uint256 amount);
    event Relocked(address indexed user, uint256 amount, uint256 lockIndex);

    /********************** Errors ***********************/
    error AddressZero();
    error AmountZero();
    error InvalidBurn();
    error InvalidLookback();
    error InvalidLockPeriod();
    error InsufficientPermission();
    error AlreadyAdded();
    error InvalidType();
    error ActiveReward();
    error InvalidAmount();
    error InvalidPeriod();
    error NotKeeper();

    /**
     * @dev Constructor
     */
    function initialize(
        address _userlist,
        address _WETH,
        uint128 _basePenaltyPercentage,
        uint128 _timePenaltyFraction
    ) public initializer {
        __Ownable_init();
        if (_userlist == address(0)) revert AddressZero();

        userlist = ILockerList(_userlist);
        WETH = _WETH;
        basePenaltyPercentage = _basePenaltyPercentage;
        timePenaltyFraction = _timePenaltyFraction;
    }

    /********************** Setters ***********************/

    /**
     * @notice Set basePenaltyPercentage
     * @dev Only owner can call
     */
    function setPenaltyCalcAttributes(uint256 _basePenaltyPercentage, uint256 _timePenaltyFraction) external onlyOwner {
        basePenaltyPercentage = _basePenaltyPercentage;
        timePenaltyFraction = _timePenaltyFraction;
    }

    /**
     * @notice Set guardians
     * @dev Can be called only once
     * @param _guardians array of address
     */
    function setGuardians(address[] calldata _guardians) external onlyOwner {
        uint256 length = _guardians.length;
        for (uint256 i; i < length; ) {
            if (_guardians[i] == address(0)) revert AddressZero();
            guardians[_guardians[i]] = true;
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Add a new reward token to be distributed to stakers.
     * @param _lockPeriod lock period array
     * @param _rewardMultipliers multipliers per lock period
     */
    function setLockTypeInfo(
        uint256[] calldata _lockPeriod,
        uint256[] calldata _rewardMultipliers
    ) external onlyOwner {
        if (_lockPeriod.length != _rewardMultipliers.length)
            revert InvalidLockPeriod();
        delete lockPeriod;
        delete rewardMultipliers;
        uint256 length = _lockPeriod.length;
        for (uint256 i; i < length; ) {
            lockPeriod.push(_lockPeriod[i]);
            rewardMultipliers.push(_rewardMultipliers[i]);
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Set staking token.
     * @param _stakingToken staking token address
     */
    function setStakingToken(address _stakingToken) external onlyOwner {
        if (_stakingToken == address(0) || stakingToken != address(0)) revert AddressZero();
        stakingToken = _stakingToken;
    }

    /**
     * @notice Set relock status
     * @param _status true if auto relock is enabled.
     */
    function setRelock(bool _status) external virtual {
        autoRelockDisabled[msg.sender] = !_status;
    }

    /**
     * @notice Set treasury address
     * @param _treasury treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    /**
     * @notice Set keeper address
     * @param _keeper keeper address
     * @param _status keeper status
     */
    function setKeeper(address _keeper, bool _status) external {
        keepers[_keeper] = _status;
    }

    /**
     * @notice Add a new reward token to be distributed to stakers.
     * @param _rewardToken address
     */
    function addReward(address _rewardToken) external override {
        if (_rewardToken == address(0)) revert InvalidBurn();
        if (!guardians[msg.sender]) revert InsufficientPermission();
        if (rewardData[_rewardToken].lastUpdateTime != 0) revert AlreadyAdded();
        rewardTokens.push(_rewardToken);

        Reward storage reward = rewardData[_rewardToken];
        reward.lastUpdateTime = block.timestamp;
    }

    /**
     * @notice Set default lock type index for user relock.
     * @param _index of default lock length
     */
    function setDefaultRelockTypeIndex(uint256 _index) external override {
        if (_index >= lockPeriod.length) revert InvalidType();
        defaultLockIndex[msg.sender] = _index;
    }

    /********************** View functions ***********************/

    /**
     * @notice Return lock duration.
     */
    function getLockDurations() external view returns (uint256[] memory) {
        return lockPeriod;
    }

    /**
     * @notice Return reward multipliers.
     */
    function getLockMultipliers() external view returns (uint256[] memory) {
        return rewardMultipliers;
    }

    /**
     * @notice Returns all locks of a user.
     * @param user address.
     * @return lockInfo of the user.
     */
    function lockInfo(
        address user
    ) external view override returns (LockedBalance[] memory) {
        return userLocks[user];
    }

    /**
     * @notice Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders.
     * @param tokenAddress to recover.
     * @param tokenAmount to recover.
     */
    function recoverERC20(
        address tokenAddress,
        uint256 tokenAmount
    ) external onlyOwner {
        if (rewardData[tokenAddress].lastUpdateTime != 0) revert ActiveReward();
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /**
     * @notice Withdraw and restake assets.
     */
    function relock() external virtual {
        uint256 amount = _withdrawExpiredLocksFor(
            msg.sender,
            true,
            false,
            userLocks[msg.sender].length
        );
        uint256 additionalAmount = expiredWithdrawable[msg.sender];
        expiredWithdrawable[msg.sender] = 0;
        _stake(amount + additionalAmount, msg.sender, defaultLockIndex[msg.sender], true);
        emit Relocked(msg.sender, amount, defaultLockIndex[msg.sender]);
    }

    /**
     * @notice recaliberate users lock status for reward calculation
     */
    // on off-chain, we pre-check all the users and just call this method only when the user has expired locks
    function reCaliberateUsersLock(address[] memory _users) external onlyKeeper {
        for (uint256 i; i < _users.length; ++ i) {
            _updateReward(_users[i]);
            _withdrawExpiredLocksFor(_users[i], false, false, userLocks[_users[i]].length);
        }
    }

    /**
     * @notice Total balance of an account, including unlocked, locked and earned tokens.
     * @param user address.
     */
    function totalBalance(
        address user
    ) external view override returns (uint256) {
        return balances[user].locked;
    }

    /**
     * @notice Information on a user's lockings
     * @return total balance of locks
     * @return unlockable balance
     * @return locked balance
     * @return lockedWithMultiplier
     * @return lockData which is an array of locks
     */
    function lockedBalances(
        address user
    )
        public
        view
        override
        returns (
            uint256,
            uint256 unlockable,
            uint256 locked,
            uint256 lockedWithMultiplier,
            LockedBalance[] memory lockData
        )
    {
        LockedBalance[] storage locks = userLocks[user];
        uint256 idx;
        uint256 length = locks.length;
        for (uint256 i; i < length; ) {
            if (locks[i].unlockTime > block.timestamp) {
                if (idx == 0) {
                    lockData = new LockedBalance[](locks.length - i);
                }
                lockData[idx] = locks[i];
                idx++;
                locked += locks[i].amount;
                lockedWithMultiplier += locks[i].amount.mul(locks[i].multiplier);
            } else {
                unlockable += locks[i].amount;
            }
            unchecked {
                i++;
            }
        }
        return (
            balances[user].locked,
            unlockable + expiredWithdrawable[user],
            locked,
            lockedWithMultiplier,
            lockData
        );
    }

    /**
     * @notice Total balance of an account, including unlocked, locked and earned tokens.
     */
    function getBalances(
        address _user
    ) external view returns (Balances memory) {
        return balances[_user];
    }

    /********************** Reward functions ***********************/

    /**
     * @notice Address and claimable amount of all reward tokens for the given account.
     * @param account for rewards
     * @return rewardsData array of rewards
     */
    function claimableRewards(
        address account
    )
        external
        view
        override
        returns (IFeeDistribution.RewardData[] memory rewardsData)
    {
        rewardsData = new IFeeDistribution.RewardData[](rewardTokens.length);
        uint256 length = rewardTokens.length;
        for (uint256 i; i < length; ) {
            rewardsData[i].token = rewardTokens[i];

            rewardsData[i].amount = (_earned(
                account,
                rewardsData[i].token
            ) + rewards[account][rewardTokens[i]]) /1e12;
            unchecked {
                i++;
            }
        }
        return rewardsData;
    }

    /********************** Operate functions ***********************/

    /**
     * @notice Stake tokens to receive rewards.
     * @dev Locked tokens cannot be withdrawn for defaultLockDuration and are eligible to receive rewards.
     * @param amount to stake.
     * @param onBehalfOf address for staking.
     * @param typeIndex lock type index.
     */
    function stake(
        uint256 amount,
        address onBehalfOf,
        uint256 typeIndex
    ) external override {
        uint256 additionalAmount = expiredWithdrawable[msg.sender];
        expiredWithdrawable[msg.sender] = 0;
        _stake(amount + additionalAmount, onBehalfOf, typeIndex, false);
    }

    /**
     * @notice Stake tokens to receive rewards.
     * @dev Locked tokens cannot be withdrawn for defaultLockDuration and are eligible to receive rewards.
     * @param amount to stake.
     * @param onBehalfOf address for staking.
     * @param typeIndex lock type index.
     * @param isRelock true if this is with relock enabled.
     */
    function _stake(
        uint256 amount,
        address onBehalfOf,
        uint256 typeIndex,
        bool isRelock
    ) internal whenNotPaused {
        if (amount == 0) return;
        if (typeIndex >= lockPeriod.length) revert InvalidAmount();

        _updateReward(onBehalfOf);
        uint256 transferAmount = amount;
        if (userLocks[onBehalfOf].length != 0) {
            //if user has any locks
            if (userLocks[onBehalfOf][0].unlockTime <= block.timestamp) {
                //if users soonest unlock has already elapsed
                if (onBehalfOf == msg.sender) {
                    uint256 withdrawnAmt;
                    if (!autoRelockDisabled[onBehalfOf]) {
                        withdrawnAmt = _withdrawExpiredLocksFor(
                            onBehalfOf,
                            true,
                            false,
                            userLocks[onBehalfOf].length
                        );
                        amount = amount.add(withdrawnAmt);
                    } else {
                        _withdrawExpiredLocksFor(
                            onBehalfOf,
                            true,
                            true,
                            userLocks[onBehalfOf].length
                        );
                    }
                }
            }
        }
        Balances storage bal = balances[onBehalfOf];

        bal.locked += amount;
        lockedSupply += amount;

        bal.lockedWithMultiplier += amount.mul(rewardMultipliers[typeIndex]);
        lockedSupplyWithMultiplier += amount.mul(rewardMultipliers[typeIndex]);
        _updateRewardDebt(onBehalfOf);

        _insertLock(
            onBehalfOf,
            LockedBalance({
                amount: amount,
                unlockTime: block.timestamp.add(lockPeriod[typeIndex]),
                multiplier: rewardMultipliers[typeIndex],
                duration: lockPeriod[typeIndex]
            })
        );

        userlist.addToList(onBehalfOf);

        if (!isRelock) {
            IERC20(stakingToken).safeTransferFrom(
                msg.sender,
                address(this),
                transferAmount
            );
        }

        emit Locked(
            onBehalfOf,
            amount,
            balances[onBehalfOf].locked
        );
    }

    /**
     * @notice Add new lockings
     * @dev We keep the array to be sorted by unlock time.
     * @param _user address of locker.
     * @param newLock new lock info.
     */
    function _insertLock(address _user, LockedBalance memory newLock) internal {
        LockedBalance[] storage locks = userLocks[_user];
        uint256 length = locks.length;
        uint256 i = _binarySearch(locks, length, newLock.unlockTime);
        locks.push();
        for (uint256 j = length; j > i; j--) {
            locks[j] = locks[j - 1];
        }
        locks[i] = newLock;
    }

    function _binarySearch(
        LockedBalance[] storage locks,
        uint256 length,
        uint256 unlockTime
    ) private view returns (uint256) {
        uint256 low = 0;
        uint256 high = length;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (locks[mid].unlockTime < unlockTime) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return low;
    }



    /**
     * @notice Claim all pending staking rewards.
     * @param _rewardTokens array of reward tokens
     */
    function getReward(address[] memory _rewardTokens) public nonReentrant {
        _updateReward(msg.sender);
        _getReward(msg.sender, _rewardTokens);
    }

    function notifyUnseenReward() external {
        uint256 length = rewardTokens.length;
        for (uint256 i; i < length; ) {
            address token = rewardTokens[i];
            _notifyUnseenReward(token);
            unchecked {
                i++;
            }
        }
    }
    /**
     * @notice Claim all pending staking rewards.
     */
    function getAllRewards() external {
        return getReward(rewardTokens);
    }

    /**
     * @notice Withdraw full unlocked balance and earnings.
     */
    function earlyExit() external {
        _updateReward(msg.sender);

        Balances storage bal = balances[msg.sender];
        uint256 amount;
        uint256 amountWithMultiplier;
        (amount, amountWithMultiplier) = _cleanWithdrawableLocks(
            msg.sender,
            bal.locked,
            bal.lockedWithMultiplier,
            1e6
        );
        uint256 penaltyAmount = calcPenaltyReward(msg.sender);

        lockedSupplyWithMultiplier -= bal.lockedWithMultiplier;
        lockedSupply -= bal.locked;
        uint256 locked = bal.locked;
        bal.lockedWithMultiplier = 0;
        bal.locked = 0;
        _updateRewardDebt(msg.sender);

        delete userLocks[msg.sender];
        userlist.removeFromList(msg.sender);

        IERC20(stakingToken).safeTransfer(msg.sender, locked - penaltyAmount);
        IERC20(stakingToken).safeTransfer(treasury, penaltyAmount);
    }

    /**
     * @notice Withdraw full unlocked balance and earnings by index.
     */
    function earlyExitByIndex(uint256 index) external {
        _updateReward(msg.sender);
        uint256 penaltyAmount = calcPenaltyRewardByIndex(msg.sender, index);
        LockedBalance[] storage userLock = userLocks[msg.sender];
        Balances storage bal = balances[msg.sender];
        lockedSupplyWithMultiplier -= bal.lockedWithMultiplier;
        lockedSupply -= bal.locked;
        bal.locked -= penaltyAmount;
        bal.lockedWithMultiplier -= userLock[index].multiplier * userLock[index].amount;
        uint256 withdrawAmount = userLock[index].amount;

        if (userLock.length == 1) {
            delete userLocks[msg.sender];
            userlist.removeFromList(msg.sender);
        } else {
            // remove data in the index
            for (uint i = index; i < userLock.length - 1; i ++) {
                userLock[index].amount = userLock[index + 1].amount;
                userLock[index].unlockTime = userLock[index + 1].unlockTime;
                userLock[index].multiplier = userLock[index + 1].multiplier;
                userLock[index].duration = userLock[index + 1].duration;
            }
            userLock.pop();
        }
        _updateRewardDebt(msg.sender);

        IERC20(stakingToken).safeTransfer(msg.sender, withdrawAmount - penaltyAmount);
        IERC20(stakingToken).safeTransfer(treasury, penaltyAmount);
    }

    /**
     * @notice Calculate earnings.
     * @param _user address of earning owner
     * @param _rewardToken address
     * @return earnings amount
     */
    function _earned(
        address _user,
        address _rewardToken
    ) internal view returns (uint256 earnings) {
        Reward memory rewardInfo = rewardData[_rewardToken];
        Balances memory balance = balances[_user];
        earnings = rewardInfo.cumulatedReward * balance.lockedWithMultiplier - rewardDebt[_user][_rewardToken];
    }

    /**
     * @notice Update user reward info.
     * @param account address
     */
    function _updateReward(address account) internal {
        uint256 length = rewardTokens.length;
        Balances storage bal = balances[account];

        for (uint256 i; i < length; ) {
            address token = rewardTokens[i];
            Reward memory rewardInfo = rewardData[token];

            if (account != address(this)) {
                rewards[account][token] += _earned(account, token);
                lastTimeClaim[account][token] = block.timestamp;
            }
            rewardDebt[account][token] = rewardInfo.cumulatedReward * bal.lockedWithMultiplier;

            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Add new reward.
     * @dev If prev reward period is not done, then it resets `rewardPerSecond` and restarts period
     * @param _rewardToken address
     * @param reward amount
     */
    function _notifyReward(address _rewardToken, uint256 reward) internal {
        Reward storage r = rewardData[_rewardToken];
        uint256 newReward = reward * 1e12 / lockedSupplyWithMultiplier;
        r.cumulatedReward += newReward;
        r.lastUpdateTime = block.timestamp;
        r.balance += reward;

        // record new rewards to array
        r.rewardByTime.push(newReward);
        r.timestamps.push(block.timestamp);
    }

    /**
     * @notice Notify unseen rewards.
     * @dev for rewards other than stakingToken, every 24 hours we check if new
     *  rewards were sent to the contract or accrued via aToken interest.
     * @param token address
     */
    function _notifyUnseenReward(address token) internal {
        // NOTE: assume the expired stakes are all removed
        if (token == address(0)) revert AddressZero();
        Reward storage r = rewardData[token];
        uint256 unseen;
        if (token == ETH_ADDRESS) {
            unseen = address(this).balance - r.balance;
        } else {
            unseen = IERC20(token).balanceOf(address(this)) - r.balance;
        }
        if (unseen > 0) {
            _notifyReward(token, unseen);
        }
    }

    function onUpgrade() public {}

    /**
     * @notice User gets reward
     * @param _user address
     * @param _rewardTokens array of reward tokens
     */
    function _getReward(
        address _user,
        address[] memory _rewardTokens
    ) internal whenNotPaused {
        uint256 length = _rewardTokens.length;
        for (uint256 i; i < length; ) {
            address token = _rewardTokens[i];

            uint256 reward = rewards[_user][token];
            if (reward > 0) {
                rewards[_user][token] = 0;
                rewardData[token].balance -= reward / 1e12;

                // wrap eth for reward
                // TODO: release native ETH
                if (token == ETH_ADDRESS) {
                    IWETH(WETH).deposit{value: reward / 1e12}();
                    IWETH(WETH).transfer(_user, reward / 1e12);
                } else {
                    IERC20(token).safeTransfer(_user, reward / 1e12);
                }
                rewardPaid[_user][token] += reward / 1e12;
                // TODO: ask if bulk event is possible. Roughly 50% cheaper
                emit RewardPaid(_user, token, reward / 1e12);
            }
            unchecked {
                i++;
            }
        }
    }

    /********************** Eligibility + Disqualification ***********************/

    /**
     * @notice Withdraw all lockings tokens where the unlock time has passed
     * @param user address
     * @param totalLock total lock amount
     * @param totalLockWithMultiplier total lock amount that is multiplied
     * @param limit limit for looping operation
     * @return lockAmount withdrawable lock amount
     * @return lockAmountWithMultiplier withdraw amount with multiplier
     */
    function _cleanWithdrawableLocks(
        address user,
        uint256 totalLock,
        uint256 totalLockWithMultiplier,
        uint256 limit
    ) internal returns (uint256 lockAmount, uint256 lockAmountWithMultiplier) {
        LockedBalance[] storage locks = userLocks[user];

        if (locks.length != 0) {
            uint256 length = locks.length <= limit ? locks.length : limit;
            uint256 i;
            while (i < length && locks[i].unlockTime <= block.timestamp) {
                lockAmount += locks[i].amount;
                lockAmountWithMultiplier += locks[i].amount.mul(locks[i].multiplier);
                i = i + 1;
            }
            for (uint256 j = i; j < locks.length; j = j + 1) {
                locks[j - i] = locks[j];
            }
            for (uint256 j = 0; j < i; j = j + 1) {
                locks.pop();
            }
            if (locks.length == 0) {
                lockAmount = totalLock;
                lockAmountWithMultiplier = totalLockWithMultiplier;
                delete userLocks[user];

                userlist.removeFromList(user);
            }
        }
    }
    
    /**
     * @notice Final balance received and penalty balance paid by user upon calling exit.
     * @dev This is earnings, not locks.
     */
    function calcPenaltyReward(address user)
        public
        view
        returns (
            uint256 penaltyAmount
        )
    {
        uint256 locked = balances[user].locked;
        if (locked > 0) {
            uint256 length = userLocks[user].length;
            for (uint256 i; i < length; i++) {
                uint256 penaltyAmountByIndex = calcPenaltyRewardByIndex(user, i);

                penaltyAmount += penaltyAmountByIndex;
            }
        }
    }

    function calcPenaltyRewardByIndex(address user, uint256 index) internal view returns (uint256 penaltyAmount) {
        LockedBalance memory userLock = userLocks[user][index];
        if (userLock.amount == 0) return 0;
        uint256 unlockTime = userLock.unlockTime;
        uint256 penaltyFactor;
        if (unlockTime > block.timestamp) {
            // 90% on day 1, decays to 25% on last day
            penaltyFactor = (unlockTime - block.timestamp)
                * timePenaltyFraction
                / userLock.duration
                + (basePenaltyPercentage); // 15% + timeLeft/duration * 35%
        }
        console2.log('penaltyFactor', penaltyFactor);
        penaltyAmount = userLock.amount.mul(penaltyFactor).div(WHOLE);        
    }
    
    function getLastTimeClaim(address _user, address _token) external view returns (uint256) {
        return lastTimeClaim[_user][_token];
    }

    /**
     * @notice Withdraw all currently locked tokens where the unlock time has passed.
     * @param _address of the user.
     * @param isRelockAction true if withdraw with relock
     * @param doTransfer true to transfer tokens to user
     * @param limit limit for looping operation
     * @return amount for withdraw
     */
    function _withdrawExpiredLocksFor(
        address _address,
        bool isRelockAction,
        bool doTransfer,
        uint256 limit
    ) internal whenNotPaused returns (uint256 amount) {
        require(
            isRelockAction == false ||
                _address == msg.sender
        );

        uint256 amountWithMultiplier;
        Balances storage bal = balances[_address];

        (amount, amountWithMultiplier) = _cleanWithdrawableLocks(
            _address,
            bal.locked,
            bal.lockedWithMultiplier,
            limit
        );
        bal.lockedWithMultiplier -= amountWithMultiplier;
        lockedSupplyWithMultiplier -= amountWithMultiplier;
        lockedSupply -= amount;
        bal.locked -= amount;
        expiredWithdrawable[_address] += amount;
        amount = 0;
        _updateRewardDebt(_address);
        uint256 additionalAmount = expiredWithdrawable[_address];
        if (!isRelockAction && !autoRelockDisabled[_address]) {
            expiredWithdrawable[_address] = 0;
            _stake(amount + additionalAmount, _address, defaultLockIndex[_address], true);
        } else {
            if (doTransfer) {
                expiredWithdrawable[_address] = 0;
                IERC20(stakingToken).safeTransfer(_address, amount + additionalAmount);
                emit Withdrawn(
                    _address,
                    amount + additionalAmount,
                    bal.locked,
                    0,
                    0
                );
            }
        }

        return amount;
    }
    
    /**
     * @notice Withdraw all currently locked tokens where the unlock time has passed.
     * @return withdraw amount
     */
    function withdrawExpiredLocksFor() external override returns (uint256) {
        _updateReward(msg.sender);
        return
            _withdrawExpiredLocksFor(
                msg.sender,
                false,
                true,
                userLocks[msg.sender].length
            );
    }

    /**
     * @notice Withdraw expired locks with options
     * @param _address for withdraw
     * @param _limit of lock length for withdraw
     * @param _ignoreRelock option to ignore relock
     * @return withdraw amount
     */
    function withdrawExpiredLocksForWithOptions(
        address _address,
        uint256 _limit,
        bool _ignoreRelock
    ) external returns (uint256) {
        if (_limit == 0) _limit = userLocks[_address].length;

        return _withdrawExpiredLocksFor(_address, _ignoreRelock, true, _limit);
    }

    function _updateRewardDebt(address _user) internal {
        Balances memory bal = balances[_user];
        for (uint i; i < rewardTokens.length; ++ i) {
            address rewardToken = rewardTokens[i];
            Reward memory rewardInfo = rewardData[rewardToken];
            rewardDebt[_user][rewardToken] = rewardInfo.cumulatedReward * bal.lockedWithMultiplier;
        }
    }

    /**
     * @notice Pause MFD functionalities
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Resume MFD functionalities
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}

    modifier onlyKeeper() {
        if (!keepers[msg.sender])
            revert NotKeeper();
        _;
    }
}

