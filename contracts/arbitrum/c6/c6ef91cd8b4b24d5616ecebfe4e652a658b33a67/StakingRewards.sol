// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.18;
import "./ERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./StakingConstants.sol";
import "./FixedPointMathLib.sol";

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
    using FixedPointMathLib for uint256;

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
        uint256 cutoffTime = startTime + ((currentLockTime * 80) / 100);

        if (currentLockTime != 0) {
            require(lockTime == currentLockTime, "StakingRewards: Cannot add stake with different lock time");
        }

        if (currentLockTime != 10 seconds && currentLockTime != 0) {
            require(block.timestamp < cutoffTime, "StakingRewards: Staking period expired");
        }

        stakeLODEInternal(amount, lockTime);
    }

    function stakeLODEInternal(uint256 amount, uint256 lockTime) internal {
        require(LODE.transferFrom(msg.sender, address(this), amount), "StakingRewards: Transfer failed");

        uint256 mintAmount = amount;
        uint256 relockAdjustment;
        uint256 threeMonthProduct;
        uint256 sixMonthProduct;
        uint256 preDivisionValue;
        uint256 threeMonthCount = stakers[msg.sender].threeMonthRelockCount;
        uint256 sixMonthCount = stakers[msg.sender].sixMonthRelockCount;

        if (lockTime == 10 seconds) {
            stakers[msg.sender].startTime = block.timestamp;
        }
        if (lockTime == 90 days) {
            mintAmount = FixedPointMathLib.mulDivDown(amount, stLODE3M, FixedPointMathLib.WAD);

            threeMonthProduct = FixedPointMathLib.mulDivDown(threeMonthCount, relockStLODE3M, FixedPointMathLib.WAD);
            sixMonthProduct = FixedPointMathLib.mulDivDown(sixMonthCount, relockStLODE6M, FixedPointMathLib.WAD);
            preDivisionValue = FixedPointMathLib.mulDivDown(
                amount,
                (threeMonthProduct + sixMonthProduct),
                FixedPointMathLib.WAD
            );
            relockAdjustment = FixedPointMathLib.mulDivDown(preDivisionValue, FixedPointMathLib.WAD, BASE);

            mintAmount += relockAdjustment;
            stakers[msg.sender].relockStLODEAmount += relockAdjustment;
            totalRelockStLODE += relockAdjustment;
        } else if (lockTime == 180 days) {
            mintAmount = FixedPointMathLib.mulDivDown(amount, stLODE6M, FixedPointMathLib.WAD);

            threeMonthProduct = FixedPointMathLib.mulDivDown(threeMonthCount, relockStLODE3M, FixedPointMathLib.WAD);
            sixMonthProduct = FixedPointMathLib.mulDivDown(sixMonthCount, relockStLODE6M, FixedPointMathLib.WAD);
            preDivisionValue = FixedPointMathLib.mulDivDown(
                amount,
                (threeMonthProduct + sixMonthProduct),
                FixedPointMathLib.WAD
            );
            relockAdjustment = FixedPointMathLib.mulDivDown(preDivisionValue, FixedPointMathLib.WAD, BASE);

            mintAmount += relockAdjustment;
            stakers[msg.sender].relockStLODEAmount += relockAdjustment;
            totalRelockStLODE += relockAdjustment; // Scale the mint amount for 6 months lock time
        }

        if (stakers[msg.sender].lodeAmount == 0) {
            stakers[msg.sender].startTime = block.timestamp;
            stakers[msg.sender].lockTime = lockTime;
        }

        stakers[msg.sender].lodeAmount += amount; // Update LODE staked amount
        stakers[msg.sender].stLODEAmount += mintAmount; // Update stLODE minted amount
        totalStaked += amount;

        UserInfo storage user = userInfo[msg.sender];

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

        // Adjust voting power
        if (lockTime != 10 seconds) {
            votingContract.mint(msg.sender, mintAmount);
        }

        emit StakedLODE(msg.sender, amount, lockTime);
    }

    /**
     * @notice Stake esLODE tokens to earn rewards
     * @param amount the amount the user wishes to stake (denom. in wei)
     */
    function stakeEsLODE(uint256 amount) external whenNotPaused nonReentrant {
        require(esLODE.balanceOf(msg.sender) >= amount, "StakingRewards: Insufficient balance");
        require(amount > 0, "StakingRewards: Invalid amount");
        EsLODEStake[] memory userStakes = esLODEStakes[msg.sender];
        require(userStakes.length <= 10, "StakingRewards: Max Number of esLODE Stakes reached");
        stakeEsLODEInternal(amount);
    }

    function stakeEsLODEInternal(uint256 amount) internal {
        require(esLODE.transferFrom(msg.sender, address(this), amount), "StakingRewards: Transfer failed");
        stakers[msg.sender].nextStakeId += 1;

        esLODEStakes[msg.sender].push(
            EsLODEStake({baseAmount: amount, amount: amount, startTimestamp: block.timestamp, alreadyConverted: 0})
        );

        stakers[msg.sender].totalEsLODEStakedByUser += amount; // Update total EsLODE staked by user
        stakers[msg.sender].stLODEAmount += amount;

        totalEsLODEStaked += amount;
        totalStaked += amount;

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

        //Adjust voting power
        votingContract.mint(msg.sender, amount);

        emit StakedEsLODE(msg.sender, amount);
    }

    /**
     * @notice Unstake LODE
     * @param amount The amount the user wishes to unstake
     */
    function unstakeLODE(uint256 amount) external nonReentrant {
        require(stakers[msg.sender].lodeAmount >= amount && amount != 0, "StakingRewards: Invalid unstake amount");
        require(
            stakers[msg.sender].startTime + stakers[msg.sender].lockTime <= block.timestamp,
            "StakingRewards: Tokens are still locked"
        );
        unstakeLODEInternal(amount);
    }

    function unstakeLODEInternal(uint256 amount) internal {
        updateShares();
        uint256 convertedAmount = _harvest();
        uint256 totalUnstake = amount + convertedAmount;

        uint256 stakedBalance = stakers[msg.sender].lodeAmount;
        uint256 stLODEBalance = stakers[msg.sender].stLODEAmount;
        uint256 relockStLODEBalance = stakers[msg.sender].relockStLODEAmount;
        uint256 esLODEBalance = stakers[msg.sender].totalEsLODEStakedByUser;
        uint256 stLODEReduction;
        uint256 lockTimePriorToUpdate = stakers[msg.sender].lockTime;

        stakers[msg.sender].stLODEAmount -= relockStLODEBalance;
        totalRelockStLODE -= relockStLODEBalance;

        //if user is withdrawing their entire staked balance, otherwise calculate appropriate stLODE reduction
        //and reset user's staking info such that their remaining balance is seen as being unlocked now
        if (totalUnstake == stakedBalance && esLODEBalance == 0) {
            //if user is unstaking entire balance and has no esLODE staked
            stakers[msg.sender].lockTime = 0;
            stakers[msg.sender].startTime = 0;
            stLODEReduction = stLODEBalance;
            stakers[msg.sender].stLODEAmount = 0;
            stakers[msg.sender].threeMonthRelockCount = 0;
            stakers[msg.sender].sixMonthRelockCount = 0;
            stakers[msg.sender].relockStLODEAmount = 0;
        } else {
            uint256 newStakedBalance = stakedBalance - totalUnstake;
            uint256 newStLODEBalance = newStakedBalance + esLODEBalance;
            stLODEReduction = stLODEBalance - newStLODEBalance;
            require(stLODEReduction <= stLODEBalance, "StakingRewards: Invalid unstake amount");
            stakers[msg.sender].stLODEAmount = newStLODEBalance;
            stakers[msg.sender].lockTime = 10 seconds;
            stakers[msg.sender].startTime = block.timestamp;
            stakers[msg.sender].threeMonthRelockCount = 0;
            stakers[msg.sender].sixMonthRelockCount = 0;
            stakers[msg.sender].relockStLODEAmount = 0;
        }

        stakers[msg.sender].lodeAmount -= totalUnstake;
        totalStaked -= totalUnstake;

        UserInfo storage user = userInfo[msg.sender];

        uint256 rewardsAdjustment;
        if (user.amount < stLODEReduction && stakers[msg.sender].totalEsLODEStakedByUser == 0) {
            rewardsAdjustment = user.amount;
        } else if (user.amount < stLODEReduction && stakers[msg.sender].totalEsLODEStakedByUser != 0) {
            rewardsAdjustment = user.amount - stakers[msg.sender].totalEsLODEStakedByUser;
        } else {
            rewardsAdjustment = stLODEReduction;
        }
        if (user.amount < rewardsAdjustment || rewardsAdjustment == 0) revert WITHDRAW_ERROR();

        unchecked {
            user.amount -= uint96(rewardsAdjustment);
            shares -= uint96(rewardsAdjustment);
        }

        user.wethRewardsDebt =
            user.wethRewardsDebt -
            int128(uint128(_calculateRewardDebt(accWethPerShare, uint96(rewardsAdjustment))));

        _burn(address(this), rewardsAdjustment);

        //Adjust voting power
        //normalize to total esLODE staked if user has any, otherwise burn to 0
        uint256 currentVotingPower = votingContract.getRawVotingPower(msg.sender);
        if (
            (lockTimePriorToUpdate != 0 && currentVotingPower != 0) ||
            (lockTimePriorToUpdate != 10 seconds && currentVotingPower != 0)
        ) {
            if (stakers[msg.sender].totalEsLODEStakedByUser != 0 && currentVotingPower != 0) {
                if (currentVotingPower > stakers[msg.sender].totalEsLODEStakedByUser) {
                    uint256 burnAmount = currentVotingPower - stakers[msg.sender].totalEsLODEStakedByUser;
                    votingContract.burn(msg.sender, burnAmount);
                } else {
                    //this shouldn't ever happen, but allow for it just in case
                    uint256 mintAmount = stakers[msg.sender].totalEsLODEStakedByUser - currentVotingPower;
                    if (mintAmount != 0) {
                        votingContract.mint(msg.sender, mintAmount);
                    }
                }
            } else if (stakers[msg.sender].totalEsLODEStakedByUser == 0 && currentVotingPower != 0) {
                votingContract.burn(msg.sender, currentVotingPower);
            }
        }

        LODE.transfer(msg.sender, totalUnstake);

        emit UnstakedLODE(msg.sender, totalUnstake);
    }

    /**
     * @notice Converts vested esLODE to LODE and updates user reward shares accordingly accounting for current lock time and relocks
     */
    function convertEsLODEToLODE() public returns (uint256) {
        //since this is also called on unstake and harvesting, we exit out of this function if user has no esLODE staked.
        if (stakers[msg.sender].totalEsLODEStakedByUser == 0) {
            return 0;
        }

        uint256 lockTime = stakers[msg.sender].lockTime;
        uint256 threeMonthCount = stakers[msg.sender].threeMonthRelockCount;
        uint256 sixMonthCount = stakers[msg.sender].sixMonthRelockCount;
        uint256 totalDays = 365 days;
        uint256 amountToTransfer;
        uint256 stLODEAdjustment;
        uint256 conversionAmount;
        uint256 innerOperation;
        uint256 result;

        EsLODEStake[] memory userStakes = esLODEStakes[msg.sender];

        for (uint256 i = 0; i < userStakes.length; i++) {
            uint256 timeDiff = (block.timestamp - userStakes[i].startTimestamp);
            uint256 alreadyConverted = userStakes[i].alreadyConverted;

            if (timeDiff >= totalDays) {
                conversionAmount = userStakes[i].amount;
                amountToTransfer += conversionAmount;
                esLODEStakes[msg.sender][i].alreadyConverted += conversionAmount;
                esLODEStakes[msg.sender][i].amount = 0;

                if (lockTime == 90 days) {
                    innerOperation =
                        (stLODE3M - 1e18) +
                        FixedPointMathLib.mulDivDown(threeMonthCount, relockStLODE3M, FixedPointMathLib.WAD) +
                        FixedPointMathLib.mulDivDown(sixMonthCount, relockStLODE6M, FixedPointMathLib.WAD);

                    result = FixedPointMathLib.mulDivDown(conversionAmount, innerOperation, BASE);
                    stLODEAdjustment += result;
                } else if (lockTime == 180 days) {
                    innerOperation =
                        (stLODE6M - 1e18) +
                        FixedPointMathLib.mulDivDown(threeMonthCount, relockStLODE3M, FixedPointMathLib.WAD) +
                        FixedPointMathLib.mulDivDown(sixMonthCount, relockStLODE6M, FixedPointMathLib.WAD);

                    stLODEAdjustment += FixedPointMathLib.mulDivDown(conversionAmount, innerOperation, BASE);
                }
            } else if (timeDiff < totalDays) {
                uint256 conversionRatioMantissa = FixedPointMathLib.mulDivDown(timeDiff, BASE, totalDays);
                conversionAmount = (FixedPointMathLib.mulDivDown(
                    userStakes[i].baseAmount,
                    conversionRatioMantissa,
                    BASE
                ) - alreadyConverted);
                amountToTransfer += conversionAmount;
                esLODEStakes[msg.sender][i].alreadyConverted += conversionAmount;
                esLODEStakes[msg.sender][i].amount -= conversionAmount;

                if (lockTime == 90 days) {
                    innerOperation =
                        (stLODE3M - 1e18) +
                        FixedPointMathLib.mulDivDown(threeMonthCount, relockStLODE3M, FixedPointMathLib.WAD) +
                        FixedPointMathLib.mulDivDown(sixMonthCount, relockStLODE6M, FixedPointMathLib.WAD);

                    stLODEAdjustment += FixedPointMathLib.mulDivDown(conversionAmount, innerOperation, BASE);
                } else if (lockTime == 180 days) {
                    innerOperation =
                        (stLODE6M - 1e18) +
                        FixedPointMathLib.mulDivDown(threeMonthCount, relockStLODE3M, FixedPointMathLib.WAD) +
                        FixedPointMathLib.mulDivDown(sixMonthCount, relockStLODE6M, FixedPointMathLib.WAD);

                    stLODEAdjustment += FixedPointMathLib.mulDivDown(conversionAmount, innerOperation, BASE);
                }
            }
        }

        //if the user has never staked LODE we need to update their state accordingly prior to any further actions
        if (stakers[msg.sender].lodeAmount == 0 && stakers[msg.sender].lockTime == 0) {
            stakers[msg.sender].lockTime = 10 seconds;
            stakers[msg.sender].startTime = block.timestamp;
        }

        stakers[msg.sender].lodeAmount += amountToTransfer;
        stakers[msg.sender].totalEsLODEStakedByUser -= amountToTransfer;

        totalEsLODEStaked -= amountToTransfer;

        if (stLODEAdjustment != 0) {
            stakers[msg.sender].stLODEAmount += stLODEAdjustment;
            UserInfo storage userRewards = userInfo[msg.sender];

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

        //Adjust voting power if user is locking LODE
        if (stakers[msg.sender].lockTime == 10 seconds || stakers[msg.sender].lockTime == 0) {
            //if user is unlocked, we need to burn their converted amount of voting power
            votingContract.burn(msg.sender, conversionAmount);
        } else {
            uint256 currentVotingPower = votingContract.getRawVotingPower(msg.sender);
            if (stakers[msg.sender].stLODEAmount > currentVotingPower) {
                uint256 votingAdjustment = stakers[msg.sender].stLODEAmount - currentVotingPower;
                votingContract.mint(msg.sender, votingAdjustment);
            } else if (stakers[msg.sender].stLODEAmount < currentVotingPower) {
                uint256 votingAdjustment = currentVotingPower - stakers[msg.sender].stLODEAmount;
                votingContract.burn(msg.sender, votingAdjustment);
            }
        }

        esLODE.transfer(address(0), amountToTransfer);

        emit esLODEConverted(msg.sender, conversionAmount);

        return conversionAmount;
    }

    /**
     * @notice Withdraw esLODE in an emergency without converting or claiming rewards
     * @dev can only be called by the end user as part of an emergency withdrawal when locks are lifted
     */
    function withdrawEsLODE() internal {
        require(locksLifted, "StakingRewards: esLODE Withdrawals Not Permitted");

        StakingInfo storage account = stakers[msg.sender];

        uint256 totalEsLODE = account.totalEsLODEStakedByUser;
        totalStaked -= totalEsLODE;
        totalEsLODEStaked -= totalEsLODE;
        stakers[msg.sender].totalEsLODEStakedByUser = 0;
        stakers[msg.sender].stLODEAmount -= totalEsLODE;

        require(
            esLODE.balanceOf(address(this)) >= totalEsLODE,
            "StakingRewards: WithdrawEsLODE: Withdraw amount exceeds contract balance"
        );

        uint256 rewardsAdjustment = totalEsLODE;

        UserInfo storage user = userInfo[msg.sender];
        if (user.amount < rewardsAdjustment || rewardsAdjustment == 0) revert WITHDRAW_ERROR();

        unchecked {
            user.amount -= uint96(rewardsAdjustment);
            shares -= uint96(rewardsAdjustment);
        }

        user.wethRewardsDebt =
            user.wethRewardsDebt -
            int128(uint128(_calculateRewardDebt(accWethPerShare, uint96(rewardsAdjustment))));

        _burn(address(this), totalEsLODE);

        //Adjust voting power
        votingContract.burn(msg.sender, totalEsLODE);

        esLODE.safeTransfer(msg.sender, totalEsLODE);
        emit UnstakedEsLODE(msg.sender, totalEsLODE);
    }

    /**
     * @notice Withdraw staked esLODE (if applicable) and LODE in an emergency without claiming rewards or converting
     * @dev can only be called by the end user when the locks are lifted
     */
    function emergencyStakerWithdrawal() external nonReentrant {
        require(locksLifted, "StakingRewards: Locks not lifted");
        updateShares();

        if (stakers[msg.sender].totalEsLODEStakedByUser != 0) {
            withdrawEsLODE();
        }

        if (stakers[msg.sender].lodeAmount == 0) {
            return;
        }

        StakingInfo storage info = stakers[msg.sender];
        UserInfo storage user = userInfo[msg.sender];

        uint256 transferAmount = info.lodeAmount;
        uint256 burnAmount = info.stLODEAmount;
        uint256 relockStLODE = info.relockStLODEAmount;

        require(
            LODE.balanceOf(address(this)) >= transferAmount,
            "StakingRewards: Transfer amount exceeds contract balance."
        );

        //update staking state
        stakers[msg.sender].lodeAmount = 0;
        stakers[msg.sender].stLODEAmount = 0;
        stakers[msg.sender].startTime = 0;
        stakers[msg.sender].lockTime = 0;
        stakers[msg.sender].relockStLODEAmount = 0;
        stakers[msg.sender].threeMonthRelockCount = 0;
        stakers[msg.sender].sixMonthRelockCount = 0;

        totalStaked -= transferAmount;
        totalRelockStLODE -= relockStLODE;

        //update rewards state
        //user should have no esLODE staked at this point so we clear out the user's rewards here
        uint256 rewardsAdjustment = user.amount;

        if (user.amount < rewardsAdjustment || rewardsAdjustment == 0) revert WITHDRAW_ERROR();

        unchecked {
            user.amount -= uint96(rewardsAdjustment);
            shares -= uint96(rewardsAdjustment);
        }

        user.wethRewardsDebt =
            user.wethRewardsDebt -
            int128(uint128(_calculateRewardDebt(accWethPerShare, uint96(rewardsAdjustment))));

        //update stLODE
        _burn(address(this), burnAmount);

        //update voting state, should have no esLODE staked here so we burn any remaining voting power
        uint256 currentVotingPower = votingContract.getRawVotingPower(msg.sender);
        votingContract.burn(msg.sender, currentVotingPower);

        //transfer user's staked LODE balance to them
        LODE.transfer(msg.sender, transferAmount);

        emit UnstakedLODE(msg.sender, transferAmount);
    }

    /**
     * @notice Relock tokens for boosted rewards
     * @param lockTime the lock time to relock the staked position for, same input options as staking function
     */
    function relock(uint256 lockTime) external whenNotPaused nonReentrant {
        require(lockTime == 90 days || lockTime == 180 days, "StakingRewards: Invalid lock time");

        //make sure user state is fresh
        convertEsLODEToLODE();
        updateShares();

        StakingInfo storage info = stakers[msg.sender];

        require(info.lockTime != 10 seconds, "StakingRewards: Cannot relock if unlocked");

        //remove current relock stLODE from total (to be re-adjusted below)
        uint256 currentRelockStLODE = info.relockStLODEAmount;
        totalRelockStLODE -= currentRelockStLODE;

        //sanity checks
        require(info.lodeAmount > 0, "StakingRewards: No stake found");
        require(
            info.startTime + FixedPointMathLib.mulDivDown(info.lockTime, 80, 100) <= block.timestamp,
            "StakingRewards: Lock time not expired"
        );

        uint256 relockStLODEAmount;
        uint256 stLODEAdjustment;
        uint256 rewardsAdjustment;
        uint256 totalEsLODEStakedByUser = info.totalEsLODEStakedByUser;

        //we need to account for changes in lock time to make sure the user is receiving the correct boost
        if (info.lockTime != lockTime) {
            //this means the user must currently be locked for 3 months and is increasing to 6 months.
            //this means their boost on their staked LODE balance increases from 140% to 200%
            if (lockTime == 180 days) {
                //calculate new relock information and stLODE balances
                stakers[msg.sender].sixMonthRelockCount += 1;
                uint256 threeMonthCount = stakers[msg.sender].threeMonthRelockCount;
                uint256 sixMonthCount = stakers[msg.sender].sixMonthRelockCount;

                uint256 relockMultiplier = 1e18 +
                    FixedPointMathLib.mulDivDown(threeMonthCount, relockStLODE3M, 1) +
                    FixedPointMathLib.mulDivDown(sixMonthCount, relockStLODE6M, 1);
                relockStLODEAmount =
                    FixedPointMathLib.mulDivDown(info.lodeAmount, relockMultiplier, BASE) -
                    info.lodeAmount;
                uint256 newStLODEBalance = FixedPointMathLib.mulDivDown(info.lodeAmount, stLODE6M, 1e18);
                newStLODEBalance += relockStLODEAmount + stakers[msg.sender].totalEsLODEStakedByUser;
                stLODEAdjustment = newStLODEBalance - info.stLODEAmount;

                //update user's state

                stakers[msg.sender].lockTime = lockTime;
                stakers[msg.sender].startTime = block.timestamp;
                stakers[msg.sender].stLODEAmount = newStLODEBalance;
                stakers[msg.sender].relockStLODEAmount = relockStLODEAmount;
                totalRelockStLODE += relockStLODEAmount;

                UserInfo storage user = userInfo[msg.sender];

                rewardsAdjustment = stakers[msg.sender].stLODEAmount - user.amount;

                uint256 _prev = totalSupply();

                unchecked {
                    user.amount += uint96(rewardsAdjustment);
                    shares += uint96(rewardsAdjustment);
                }

                user.wethRewardsDebt =
                    user.wethRewardsDebt +
                    int128(uint128(_calculateRewardDebt(accWethPerShare, uint96(rewardsAdjustment))));

                _mint(address(this), rewardsAdjustment);

                //Adjust voting power
                uint256 currentVotingPower = votingContract.getRawVotingPower(msg.sender);
                votingContract.burn(msg.sender, currentVotingPower);
                votingContract.mint(msg.sender, stakers[msg.sender].stLODEAmount);

                unchecked {
                    if (_prev + rewardsAdjustment != totalSupply()) revert DEPOSIT_ERROR();
                }
            } else {
                //the lock time must be going from 6 months to 3 months,
                //which means we need to decrease their boost to 140% from 200%
                //calculate new relock multiplier and stLODE balances
                stakers[msg.sender].threeMonthRelockCount += 1;
                uint256 threeMonthCount = stakers[msg.sender].threeMonthRelockCount;
                uint256 sixMonthCount = stakers[msg.sender].sixMonthRelockCount;
                uint256 relockMultiplier = 1e18 +
                    FixedPointMathLib.mulDivDown(threeMonthCount, relockStLODE3M, 1) +
                    FixedPointMathLib.mulDivDown(sixMonthCount, relockStLODE6M, 1);
                relockStLODEAmount =
                    FixedPointMathLib.mulDivDown(info.lodeAmount, relockMultiplier, BASE) -
                    info.lodeAmount;
                uint256 newStLODEBalance = FixedPointMathLib.mulDivDown(info.lodeAmount, stLODE3M, 1e18);
                newStLODEBalance += relockStLODEAmount + stakers[msg.sender].totalEsLODEStakedByUser;
                stLODEAdjustment = info.stLODEAmount - newStLODEBalance;

                //update user's state
                stakers[msg.sender].lockTime = lockTime;
                stakers[msg.sender].startTime = block.timestamp;
                stakers[msg.sender].stLODEAmount = newStLODEBalance;
                stakers[msg.sender].relockStLODEAmount = relockStLODEAmount;
                totalRelockStLODE += relockStLODEAmount;

                UserInfo storage user = userInfo[msg.sender];

                rewardsAdjustment = user.amount - stakers[msg.sender].stLODEAmount;

                if (user.amount < rewardsAdjustment || rewardsAdjustment == 0) revert WITHDRAW_ERROR();

                unchecked {
                    user.amount -= uint96(rewardsAdjustment);
                    shares -= uint96(rewardsAdjustment);
                }

                user.wethRewardsDebt =
                    user.wethRewardsDebt -
                    int128(uint128(_calculateRewardDebt(accWethPerShare, uint96(rewardsAdjustment))));

                //Adjust voting power
                uint256 currentVotingPower = votingContract.getRawVotingPower(msg.sender);
                votingContract.burn(msg.sender, currentVotingPower);
                votingContract.mint(msg.sender, stakers[msg.sender].stLODEAmount);

                _burn(address(this), rewardsAdjustment);
            }
        } else {
            //if lock time is the same as previous lock, we do similar calculations
            if (lockTime == 180 days) {
                //calculate new relock multiplier and stLODE balances
                //we only need to add the new relock stLODE to state and rewards as base stLODE stays the same
                stakers[msg.sender].sixMonthRelockCount += 1;
                uint256 threeMonthCount = stakers[msg.sender].threeMonthRelockCount;
                uint256 sixMonthCount = stakers[msg.sender].sixMonthRelockCount;
                uint256 innerCalculation = 1e18 +
                    FixedPointMathLib.mulDivDown(threeMonthCount, relockStLODE3M, 1) +
                    FixedPointMathLib.mulDivDown(sixMonthCount, relockStLODE6M, 1);
                relockStLODEAmount =
                    FixedPointMathLib.mulDivDown(info.lodeAmount, innerCalculation, BASE) -
                    info.lodeAmount;
                uint256 newStLODEBalance = FixedPointMathLib.mulDivDown(info.lodeAmount, stLODE6M, 1e18);
                newStLODEBalance += relockStLODEAmount;

                //update user's state
                stakers[msg.sender].lockTime = lockTime;
                stakers[msg.sender].startTime = block.timestamp;
                stakers[msg.sender].stLODEAmount = newStLODEBalance + totalEsLODEStakedByUser;
                stakers[msg.sender].relockStLODEAmount = relockStLODEAmount;
                totalRelockStLODE += relockStLODEAmount;

                UserInfo storage user = userInfo[msg.sender];

                rewardsAdjustment = stakers[msg.sender].stLODEAmount - user.amount;

                uint256 _prev = totalSupply();

                unchecked {
                    user.amount += uint96(rewardsAdjustment);
                    shares += uint96(rewardsAdjustment);
                }

                user.wethRewardsDebt =
                    user.wethRewardsDebt +
                    int128(uint128(_calculateRewardDebt(accWethPerShare, uint96(rewardsAdjustment))));

                //Adjust voting power
                uint256 currentVotingPower = votingContract.getRawVotingPower(msg.sender);
                votingContract.burn(msg.sender, currentVotingPower);
                votingContract.mint(msg.sender, stakers[msg.sender].stLODEAmount);

                _mint(address(this), rewardsAdjustment);

                unchecked {
                    if (_prev + rewardsAdjustment != totalSupply()) revert DEPOSIT_ERROR();
                }
            } else {
                //calculate new relock multiplier and stLODE balances
                //we only need to add the new relock stLODE to state and rewards as base stLODE stays the same
                stakers[msg.sender].threeMonthRelockCount += 1;
                uint256 threeMonthCount = stakers[msg.sender].threeMonthRelockCount;
                uint256 sixMonthCount = stakers[msg.sender].sixMonthRelockCount;
                uint256 innerCalculation = 1e18 +
                    FixedPointMathLib.mulDivDown(threeMonthCount, relockStLODE3M, 1) +
                    FixedPointMathLib.mulDivDown(sixMonthCount, relockStLODE6M, 1);
                relockStLODEAmount =
                    FixedPointMathLib.mulDivDown(info.lodeAmount, innerCalculation, BASE) -
                    info.lodeAmount;
                uint256 newStLODEBalance = FixedPointMathLib.mulDivDown(info.lodeAmount, stLODE3M, 1e18);
                newStLODEBalance += relockStLODEAmount;

                //update user's state
                stakers[msg.sender].lockTime = lockTime;
                stakers[msg.sender].startTime = block.timestamp;
                stakers[msg.sender].stLODEAmount = newStLODEBalance + totalEsLODEStakedByUser;
                stakers[msg.sender].relockStLODEAmount = relockStLODEAmount;
                totalRelockStLODE += relockStLODEAmount;

                UserInfo storage user = userInfo[msg.sender];

                rewardsAdjustment = stakers[msg.sender].stLODEAmount - user.amount;

                uint256 _prev = totalSupply();

                unchecked {
                    user.amount += uint96(rewardsAdjustment);
                    shares += uint96(rewardsAdjustment);
                }

                user.wethRewardsDebt =
                    user.wethRewardsDebt +
                    int128(uint128(_calculateRewardDebt(accWethPerShare, uint96(rewardsAdjustment))));

                //Adjust voting power
                uint256 currentVotingPower = votingContract.getRawVotingPower(msg.sender);
                votingContract.burn(msg.sender, currentVotingPower);
                votingContract.mint(msg.sender, stakers[msg.sender].stLODEAmount);

                _mint(address(this), rewardsAdjustment);

                unchecked {
                    if (_prev + rewardsAdjustment != totalSupply()) revert DEPOSIT_ERROR();
                }
            }
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
        _harvest();
    }

    function _harvest() private returns (uint256) {
        updateShares();
        uint256 convertedAmount = convertEsLODEToLODE();
        UserInfo storage user = userInfo[msg.sender];

        uint256 wethPending = _calculatePending(user.wethRewardsDebt, accWethPerShare, user.amount);

        user.wethRewardsDebt = int128(uint128(_calculateRewardDebt(accWethPerShare, user.amount)));

        WETH.safeTransfer(msg.sender, wethPending);

        emit RewardsClaimed(msg.sender, wethPending);

        return convertedAmount;
    }

    /**
     * @notice Function to calculate a user's rewards per share
     * @param _rewardRatePerSecond The current reward rate determined by the updateWeeklyRewards function
     */
    function rewardPerShare(uint256 _rewardRatePerSecond) public view returns (uint128) {
        unchecked {
            return
                uint128(
                    FixedPointMathLib.mulDivDown(
                        FixedPointMathLib.mulDivDown((block.timestamp - lastRewardSecond), _rewardRatePerSecond, 1),
                        MUL_CONSTANT,
                        shares
                    )
                );
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
            if (int128(uint128(_calculateRewardDebt(_accPerShare, _amount))) < _rewardDebt) {
                return 0;
            }
            return uint128(_calculateRewardDebt(_accPerShare, _amount)) - uint128(_rewardDebt);
        }
    }

    function _calculateRewardDebt(uint256 _accWethPerShare, uint96 _amount) internal pure returns (uint256) {
        unchecked {
            return FixedPointMathLib.mulDivDown(_amount, _accWethPerShare, MUL_CONSTANT);
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
        updateShares();
        weeklyRewards = _weeklyRewards;
        lastUpdateTimestamp = block.timestamp;
        setStartTime(uint32(block.timestamp));
        uint256 _wethPerSecond = calculateWethPerSecond(_weeklyRewards);
        setEmission(_wethPerSecond);
        emit WeeklyRewardsUpdated(_weeklyRewards);
    }

    /**
     * @notice Function used to return current user's staked LODE amount
     * @param _address The staker's address
     * @return Returns the user's currently staked LODE amount
     */
    function getStLODEAmount(address _address) public view returns (uint256) {
        return stakers[_address].stLODEAmount;
    }

    /**
     * @notice Function used to return curren user's staked LODE lockTime
     * @param _address The staker's address
     * @return Returns the user's currently staked LODE lockTime
     */
    function getStLodeLockTime(address _address) public view returns (uint256) {
        return stakers[_address].lockTime;
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
        require(_routerContract != address(0), "StakingRewards: Invalid Router Contract");
        routerContract = _routerContract;
        emit RouterContractUpdated(_routerContract);
    }

    /**
     * @notice Admin function to update the voting power contract
     * @dev Can only be called by contract owner
     */
    function _updateVotingContract(address _votingContract) external onlyOwner {
        require(_votingContract != address(0), "StakingRewards: Invalid Voting Contract");
        votingContract = IVotingPower(_votingContract);
        emit VotingContractUpdated(address(votingContract));
    }

    /**
     * @notice Admin function to withdraw esLODE backing LODE in an emergency scenario
     * @dev Can only be called by contract owner, and can only withdraw LODE that is not staked by users.
     */
    function _emergencyWithdraw() external onlyOwner {
        uint256 contractLODEBalance = LODE.balanceOf(address(this));
        uint256 LODEDelta = contractLODEBalance - (totalStaked - totalEsLODEStaked);
        LODE.transfer(owner(), LODEDelta);
        emit EmergencyWithdrawal(LODEDelta);
    }

    /**
     * @notice Admin function to allow stakers to unstake their tokens immediately
     * @param state true = locks are lifted. defaults to false (locks are not lifted)
     * @dev Can only be called by contract owner.
     */
    function _liftLocks(bool state) external onlyOwner {
        locksLifted = state;
        emit LocksLifted(locksLifted, block.timestamp);
    }
}

