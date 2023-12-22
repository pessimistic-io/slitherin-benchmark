// SPDX-License-Identifier: BSD-3-Clause

pragma solidity ^0.8.0;
import "./ERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./StakingConstants.sol";

/**
 * @title Lodestar Finance Staking Contract
 * @author Lodestar Finance
 */

contract StakingRewards is
    StakingConstants,
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    Ownable2StepUpgradeable,
    ERC20Upgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     * @notice initializer function
     * @param _LODE LODE token address
     * @param _WETH WETH address
     * @param _esLODE esLODE address
     * @param _routerContract Router address
     * @dev can only be called once
     */
    function initialize(address _LODE, address _WETH, address _esLODE, address _routerContract) public initializer {
        __Context_init();
        __Ownable2Step_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init("Staking LODE", "stLODE");

        LODE = IERC20Upgradeable(_LODE);
        WETH = IERC20Upgradeable(_WETH);
        esLODE = IERC20Upgradeable(_esLODE);
        routerContract = _routerContract;

        stLODE3M = 1400000000000000000;
        stLODE6M = 2000000000000000000;
        relockStLODE3M = 50000000000000000;
        relockStLODE6M = 100000000000000000;

        WETH.approve(address(this), type(uint256).max);

        lastRewardSecond = uint32(block.timestamp);
    }

    /**
     * @notice Stake LODE with or without a lock time to earn rewards
     * @param amount the amount the user wishes to stake (denom. in wei)
     * @param lockTime the desired lock time. Must be 10 seconds, 90 days (in seconds) or 180 days (in seconds)
     */
    function stakeLODE(uint256 amount, uint256 lockTime) external whenNotPaused nonReentrant {
        require(amount != 0, "StakingRewards: Invalid stake amount");
        require(
            lockTime == 10 seconds || lockTime == 90 days || lockTime == 180 days,
            "StakingRewards: Invalid lock time"
        );
        uint256 currentLockTime = stakers[msg.sender].lockTime;
        uint256 startTime = stakers[msg.sender].startTime;
        uint256 unlockTime = startTime + currentLockTime;

        if (currentLockTime != 0) {
            require(lockTime == currentLockTime, "StakingRewards: Cannot add stake with different lock time");
        }

        if (currentLockTime != 10 seconds && currentLockTime != 0) {
            require(block.timestamp < unlockTime, "StakingRewards: Staking period expired");
        }

        stakeLODEInternal(msg.sender, amount, lockTime);
    }

    function stakeLODEInternal(address staker, uint256 amount, uint256 lockTime) internal {
        require(LODE.transferFrom(staker, address(this), amount), "StakingRewards: Transfer failed");

        uint256 mintAmount = amount;

        if (lockTime == 90 days) {
            mintAmount = (amount * stLODE3M) / 1e18; // Scale the mint amount for 3 months lock time
        } else if (lockTime == 180 days) {
            mintAmount = (amount * stLODE6M) / 1e18; // Scale the mint amount for 6 months lock time
        }

        if (stakers[staker].lodeAmount == 0) {
            stakers[staker].startTime = block.timestamp;
            stakers[staker].lockTime = lockTime;
        }

        stakers[staker].lodeAmount += amount; // Update LODE staked amount
        stakers[staker].stLODEAmount += mintAmount; // Update stLODE minted amount
        totalStaked += amount;

        UserInfo storage user = userInfo[staker];

        uint256 _prev = totalSupply();

        updateShares();

        unchecked {
            user.amount += uint96(mintAmount);
            shares += uint96(mintAmount);
        }

        user.wethRewardsDebt =
            user.wethRewardsDebt +
            int128(uint128(_calculateRewardDebt(accWethPerShare, uint96(mintAmount))));

        _mint(address(this), mintAmount);

        unchecked {
            if (_prev + mintAmount != totalSupply()) revert DEPOSIT_ERROR();
        }

        emit StakedLODE(staker, amount, lockTime);
    }

    /**
     * @notice Stake esLODE tokens to earn rewards
     * @param amount the amount the user wishes to stake (denom. in wei)
     */
    function stakeEsLODE(uint256 amount) external whenNotPaused nonReentrant {
        require(esLODE.balanceOf(msg.sender) >= amount, "StakingRewards: Insufficient balance");
        require(amount > 0, "StakingRewards: Invalid amount");
        stakeEsLODEInternal(amount);
    }

    function stakeEsLODEInternal(uint256 amount) internal {
        require(esLODE.transferFrom(msg.sender, address(this), amount), "StakingRewards: Transfer failed");
        stakers[msg.sender].nextStakeId += 1;

        esLODEStakes[msg.sender].push(Stake({amount: amount, startTimestamp: block.timestamp, alreadyConverted: 0}));

        stakers[msg.sender].totalEsLODEStakedByUser += amount; // Update total EsLODE staked by user
        totalStaked += amount;
        stakers[msg.sender].stLODEAmount += amount;
        totalEsLODEStaked += amount;

        UserInfo storage user = userInfo[msg.sender];

        uint256 _prev = totalSupply();

        updateShares();

        unchecked {
            user.amount += uint96(amount);
            shares += uint96(amount);
        }

        user.wethRewardsDebt =
            user.wethRewardsDebt +
            int128(uint128(_calculateRewardDebt(accWethPerShare, uint96(amount))));

        _mint(address(this), amount);

        unchecked {
            if (_prev + amount != totalSupply()) revert DEPOSIT_ERROR();
        }
        emit StakedEsLODE(msg.sender, amount);
    }

    /**
     * @notice Unstake LODE
     * @param amount The amount the user wishes to unstake
     */
    function unstakeLODE(uint256 amount) external nonReentrant {
        convertEsLODEToLODE(msg.sender);
        require(stakers[msg.sender].lodeAmount >= amount && amount != 0, "StakingRewards: Invalid unstake amount");
        require(
            stakers[msg.sender].startTime + stakers[msg.sender].lockTime <= block.timestamp,
            "StakingRewards: Tokens are still locked"
        );
        unstakeLODEInternal(msg.sender, amount);
    }

    function unstakeLODEInternal(address staker, uint256 amount) internal {
        updateShares();
        _harvest(staker);

        uint256 stakedBalance = stakers[staker].lodeAmount;
        uint256 stLODEBalance = stakers[staker].stLODEAmount;
        uint256 relockStLODEBalance = stakers[staker].relockStLODEAmount;
        uint256 esLODEBalance = stakers[staker].totalEsLODEStakedByUser;
        uint256 stLODEReduction;

        stakers[staker].stLODEAmount -= relockStLODEBalance;
        totalRelockStLODE -= relockStLODEBalance;

        //if user is withdrawing their entire staked balance, otherwise calculate appropriate stLODE reduction
        //and reset user's staking info such that their remaining balance is seen as being unlocked now

        if (amount == stakedBalance && esLODEBalance == 0) {
            //if user is unstaking entire balance and has no esLODE staked
            stakers[staker].lockTime = 0;
            stakers[staker].startTime = 0;
            stLODEReduction = stLODEBalance;
            stakers[staker].stLODEAmount = 0;
            stakers[staker].threeMonthRelockCount = 0;
            stakers[staker].sixMonthRelockCount = 0;
        } else {
            uint256 newStakedBalance = stakedBalance - amount;
            uint256 newStLODEBalance = newStakedBalance + esLODEBalance;
            stLODEReduction = stLODEBalance - newStLODEBalance;
            require(stLODEReduction <= stLODEBalance, "StakingRewards: Invalid unstake amount");
            stakers[staker].stLODEAmount = newStLODEBalance;
            stakers[staker].lockTime = 10 seconds;
            stakers[staker].startTime = block.timestamp;
            stakers[staker].threeMonthRelockCount = 0;
            stakers[staker].sixMonthRelockCount = 0;
        }

        stakers[staker].lodeAmount -= amount;
        totalStaked -= amount;

        UserInfo storage user = userInfo[staker];
        if (user.amount < stLODEReduction || stLODEReduction == 0) revert WITHDRAW_ERROR();

        unchecked {
            user.amount -= uint96(stLODEReduction);
            shares -= uint96(stLODEReduction);
        }

        user.wethRewardsDebt =
            user.wethRewardsDebt -
            int128(uint128(_calculateRewardDebt(accWethPerShare, uint96(stLODEReduction))));

        _burn(address(this), stLODEReduction);
        LODE.transfer(staker, amount);

        emit UnstakedLODE(staker, amount);
    }

    /**
     * @notice Converts vested esLODE to LODE and updates user reward shares accordingly accounting for current lock time and relocks
     * @param user The staker's address
     */
    function convertEsLODEToLODE(address user) public returns (uint256) {
        //since this is also called on unstake and harvesting, we exit out of this function if user has no esLODE staked.
        if (stakers[msg.sender].totalEsLODEStakedByUser == 0) {
            return 0;
        }

        uint256 lockTime = stakers[user].lockTime;
        uint256 threeMonthCount = stakers[user].threeMonthRelockCount;
        uint256 sixMonthCount = stakers[user].sixMonthRelockCount;
        uint256 totalDays = 365 days;
        uint256 amountToTransfer;
        uint256 stLODEAdjustment;
        uint256 conversionAmount;

        Stake[] memory userStakes = esLODEStakes[msg.sender];

        for (uint256 i = 0; i < userStakes.length; i++) {
            uint256 timeDiff = (block.timestamp - userStakes[i].startTimestamp);
            uint256 alreadyConverted = userStakes[i].alreadyConverted;

            if (timeDiff >= totalDays) {
                conversionAmount = userStakes[i].amount;
                amountToTransfer += conversionAmount;
                userStakes[i].amount = 0;
                if (lockTime == 90 days) {
                    stLODEAdjustment +=
                        (conversionAmount *
                            ((stLODE3M - 1e18) +
                                (threeMonthCount * relockStLODE3M) +
                                (sixMonthCount * relockStLODE6M))) /
                        BASE;
                } else if (lockTime == 180 days) {
                    stLODEAdjustment +=
                        (conversionAmount *
                            ((stLODE6M - 1e18) +
                                (threeMonthCount * relockStLODE3M) +
                                (sixMonthCount * relockStLODE6M))) /
                        BASE;
                }
            } else if (timeDiff < totalDays) {
                uint256 conversionRatioMantissa = (timeDiff * BASE) / totalDays;
                conversionAmount = ((userStakes[i].amount * conversionRatioMantissa) / BASE) - alreadyConverted;
                amountToTransfer += conversionAmount;
                alreadyConverted += conversionAmount;
                userStakes[i].amount -= conversionAmount;
                if (lockTime == 90 days) {
                    stLODEAdjustment +=
                        (conversionAmount *
                            ((stLODE3M - 1e18) +
                                (threeMonthCount * relockStLODE3M) +
                                (sixMonthCount * relockStLODE6M))) /
                        BASE;
                } else if (lockTime == 180 days) {
                    stLODEAdjustment +=
                        (conversionAmount *
                            ((stLODE6M - 1e18) +
                                (threeMonthCount * relockStLODE3M) +
                                (sixMonthCount * relockStLODE6M))) /
                        BASE;
                }
            }
        }

        stakers[user].lodeAmount += amountToTransfer;
        stakers[user].totalEsLODEStakedByUser -= amountToTransfer;

        if (stLODEAdjustment != 0) {
            stakers[user].stLODEAmount += stLODEAdjustment;
            UserInfo storage userRewards = userInfo[user];

            uint256 _prev = totalSupply();

            updateShares();

            unchecked {
                userRewards.amount += uint96(stLODEAdjustment);
                shares += uint96(stLODEAdjustment);
            }

            userRewards.wethRewardsDebt =
                userRewards.wethRewardsDebt +
                int128(uint128(_calculateRewardDebt(accWethPerShare, uint96(stLODEAdjustment))));

            _mint(address(this), stLODEAdjustment);

            unchecked {
                if (_prev + stLODEAdjustment != totalSupply()) revert DEPOSIT_ERROR();
            }
        }

        esLODE.transfer(address(0), amountToTransfer);
        return conversionAmount;
    }

    /**
     * @notice Withdraw esLODE
     * @dev can only be called by the end user when withdrawing of esLODE is allowed
     */
    function withdrawEsLODE() external nonReentrant {
        require(withdrawEsLODEAllowed == true, "esLODE Withdrawals Not Permitted");
        //harvest();
        StakingInfo storage account = stakers[msg.sender];
        uint256 totalEsLODE = account.totalEsLODEStakedByUser;
        esLODE.safeTransfer(msg.sender, totalEsLODE);
        emit UnstakedEsLODE(msg.sender, totalEsLODE);
    }

    /**
     * @notice Relock tokens for boosted rewards
     * @param lockTime the lock time to relock the staked position for, same input options as staking function
     */
    function relock(uint256 lockTime) external whenNotPaused nonReentrant {
        require(lockTime == 90 days || lockTime == 180 days, "StakingRewards: Invalid lock time");
        StakingInfo storage info = stakers[msg.sender];
        require(info.lodeAmount > 0, "StakingRewards: No stake found");
        require(info.startTime + info.lockTime <= block.timestamp, "StakingRewards: Lock time not expired");

        convertEsLODEToLODE(msg.sender);

        // Calculate vstLODE to mint based on the previous lock period
        uint256 stakeAmount;
        if (info.lockTime == 90 days) {
            stakeAmount = (info.lodeAmount * relockStLODE3M) / 1e18;
            info.threeMonthRelockCount += 1;
        } else if (info.lockTime == 180 days) {
            stakeAmount = (info.lodeAmount * relockStLODE6M) / 1e18;
            info.sixMonthRelockCount += 1;
        }

        // Update stake with new lock period and mint vstLODE tokens
        info.lockTime = lockTime;
        info.startTime = block.timestamp;
        info.stLODEAmount += stakeAmount;
        info.relockStLODEAmount += stakeAmount;
        totalRelockStLODE += stakeAmount;

        UserInfo storage user = userInfo[msg.sender];

        uint256 _prev = totalSupply();

        updateShares();

        unchecked {
            user.amount += uint96(stakeAmount);
            shares += uint96(stakeAmount);
        }

        user.wethRewardsDebt =
            user.wethRewardsDebt +
            int128(uint128(_calculateRewardDebt(accWethPerShare, uint96(stakeAmount))));

        _mint(address(this), stakeAmount);

        unchecked {
            if (_prev + stakeAmount != totalSupply()) revert DEPOSIT_ERROR();
        }

        emit Relocked(msg.sender, lockTime);
    }

    /**
     * @notice Update the staking rewards information to be current
     * @dev Called before all reward state changing functions
     */
    function updateShares() public {
        // if block.timestamp <= lastRewardSecond, already updated.
        if (block.timestamp <= lastRewardSecond) {
            return;
        }

        // if pool has no supply
        if (shares == 0) {
            lastRewardSecond = uint32(block.timestamp);
            return;
        }

        unchecked {
            accWethPerShare += rewardPerShare(wethPerSecond);
        }

        lastRewardSecond = uint32(block.timestamp);
    }

    /**
     * @notice Function for a user to claim their pending rewards
     * @dev Reverts on transfer failure via SafeERC20
     */
    function claimRewards() external nonReentrant {
        uint256 stakedLODE = stakers[msg.sender].lodeAmount;
        uint256 stakedEsLODE = stakers[msg.sender].totalEsLODEStakedByUser;
        if (stakedLODE == 0 && stakedEsLODE == 0) {
            revert("StakingRewards: No staked balance");
        }
        _harvest(msg.sender);
    }

    function _harvest(address _user) private {
        updateShares();
        convertEsLODEToLODE(msg.sender);
        UserInfo storage user = userInfo[_user];

        uint256 wethPending = _calculatePending(user.wethRewardsDebt, accWethPerShare, user.amount);

        user.wethRewardsDebt = int128(uint128(_calculateRewardDebt(accWethPerShare, user.amount)));

        WETH.safeTransfer(_user, wethPending);

        emit RewardsClaimed(_user, wethPending);
    }

    /**
     * @notice Function to calculate a user's rewards per share
     * @param _rewardRatePerSecond The current reward rate determined by the updateWeeklyRewards function
     */
    function rewardPerShare(uint256 _rewardRatePerSecond) public view returns (uint128) {
        unchecked {
            return uint128(((block.timestamp - lastRewardSecond) * _rewardRatePerSecond * MUL_CONSTANT) / shares);
        }
    }

    /**
     * @notice Function to calculate a user's pending rewards to be ingested by FE
     * @param _user The staker's address
     */
    function pendingRewards(address _user) external view returns (uint256 _pendingweth) {
        uint256 _wethPS = accWethPerShare;

        if (block.timestamp > lastRewardSecond && shares != 0) {
            _wethPS += rewardPerShare(wethPerSecond);
        }

        UserInfo memory user = userInfo[_user];

        _pendingweth = _calculatePending(user.wethRewardsDebt, _wethPS, user.amount);
    }

    function _calculatePending(
        int128 _rewardDebt,
        uint256 _accPerShare, // Stay 256;
        uint96 _amount
    ) internal pure returns (uint128) {
        if (_rewardDebt < 0) {
            return uint128(_calculateRewardDebt(_accPerShare, _amount)) + uint128(-_rewardDebt);
        } else {
            return uint128(_calculateRewardDebt(_accPerShare, _amount)) - uint128(_rewardDebt);
        }
    }

    function _calculateRewardDebt(uint256 _accWethPerShare, uint96 _amount) internal pure returns (uint256) {
        unchecked {
            return (_amount * _accWethPerShare) / MUL_CONSTANT;
        }
    }

    function setStartTime(uint32 _startTime) internal {
        lastRewardSecond = _startTime;
    }

    function setEmission(uint256 _wethPerSecond) internal {
        wethPerSecond = _wethPerSecond;
    }

    /**
     * @notice Function to calculate the current WETH/second rewards rate
     * @param rewardsAmount The current weekly rewards amount (denom. in wei)
     */
    function calculateWethPerSecond(uint256 rewardsAmount) public pure returns (uint256 _wethPerSecond) {
        uint256 periodDuration = 7 days;
        _wethPerSecond = rewardsAmount / periodDuration;
    }

    /**
     * @notice Permissioned function to update weekly rewards
     * @param _weeklyRewards The amount of incoming weekly rewards
     * @dev Can only be called by the router contract
     */
    function updateWeeklyRewards(uint256 _weeklyRewards) external {
        require(msg.sender == routerContract, "StakingRewards: Unauthorized");
        weeklyRewards = _weeklyRewards;
        lastUpdateTimestamp = block.timestamp;
        setStartTime(uint32(block.timestamp));
        uint256 _wethPerSecond = calculateWethPerSecond(_weeklyRewards);
        setEmission(_wethPerSecond);
        emit WeeklyRewardsUpdated(_weeklyRewards);
    }

    /**
     * @notice Function used to calculate a user's voting power for emissions voting
     * @param account The staker's address
     * @return Returns the user's voting power as a percentage of the total voting power
     */
    function accountVoteShare(address account) public view returns (uint256) {
        uint256 stLODEStaked = stakers[account].stLODEAmount;
        uint256 vstLODEStaked = stakers[account].relockStLODEAmount;
        uint256 totalStLODEStaked = totalSupply() - totalRelockStLODE;
        uint256 totalVstLODEStaked = totalRelockStLODE;

        uint256 totalStakedAmount = stLODEStaked + vstLODEStaked;
        uint256 totalStakedBalance = totalStLODEStaked + totalVstLODEStaked;

        if (totalStakedBalance == 0) {
            return 0;
        }

        return (totalStakedAmount * 1e18) / totalStakedBalance;
    }

    /* **ADMIN FUNCTIONS** */

    /**
     * @notice Pause function for staking operations
     * @dev Can only be called by contract owner
     */
    function _pauseStaking() external onlyOwner {
        _pause();
        emit StakingPaused();
    }

    /**
     * @notice Unause function for staking operations
     * @dev Can only be called by contract owner
     */
    function _unpauseStaking() external onlyOwner {
        _unpause();
        emit StakingUnpaused();
    }

    /**
     * @notice Admin function to update the router contract
     * @dev Can only be called by contract owner
     */
    function _updateRouterContract(address _routerContract) external onlyOwner {
        routerContract = _routerContract;
        emit RouterContractUpdated(_routerContract);
    }

    /**
     * @notice Admin function to toggle whether esLODE withdraws are allowed
     * @param state Desired state of esLODE withdrawals. True = allowed.
     * @dev Can only be called by contract owner
     */
    function _allowEsLODEWithdraw(bool state) external onlyOwner {
        withdrawEsLODEAllowed = state;
        emit esLODEUnlocked(state, block.timestamp);
    }
}

