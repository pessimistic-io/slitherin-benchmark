// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ERC2771Context.sol";
import "./Initializable.sol";

import "./IBlxToken.sol";
import "./IAccessContract.sol";
import "./IBlxOracle.sol";
import "./IFormulas.sol";
import "./ITreasury.sol";
import "./IStakingContract.sol";
import "./IRewardsDistributionRecipient.sol";
import "./IStakingSnapshot.sol";
import "./IBlxStaking.sol";
import "./StakingRewards.sol";

import {Abdk} from "./AbdkUtil.sol";

import "./console.sol";

contract StakingContract is
    IStakingContract, ERC2771Context, AccessContract, Initializable,
    StakingRewards
{
    using Abdk for uint;
    using ABDKMath64x64 for int128;

    uint public constant WEEK_PERIOD = 7 * 86400;
    uint128 public constant LOCKED_TIME = 86400; // deposit is locked for 1 day before it can be withdrawn, even for unlock deposit
    uint public constant YEAR_PERIOD = 52 * 7 * 86400; // 364 days
    uint public constant MAX_LOCK_DURATION_WEEKS = 52;
    uint public constant PCT_BURN_DEFAULT = 500;
    uint public constant EMPTY_BARRIER = 1000; // USD barrier indicate staking pool is empty(not zero due to rounding)
    uint public minBlxAmount;    // minimum blx stake amount
    uint public minUsdAmount; // minimum stable token stake amount
    uint public constant PCT_BLX_PORTION = 2000; // 20% of reward goes to BLX staking
    uint public pctBurn;

    IFormulas public formulas;
    IBlxOracle public priceOracle;
    ITreasury public treasury;
    IStakingSnapshot public stakingSnapshot;
    IBlxStaking public blxStaking;

    address public USD;
    address public BLX;
    bool sunsetting;

    uint lastDistributeDate;

    event StakeAdded(address indexed user, uint usdAmount, uint blxAmount);
    event StakeWithdrawn(address indexed user, uint usdAmount, uint blxAmount);
    event RewardStaked(address indexed user, uint usdAmount);
    event LockApplied(address indexed user, uint duration);
    event NewStaker(address indexed user, uint usdAmount, uint blxAmount);
    event RemovedStaker(address indexed user, uint usdAmount, uint blxAmount);

    struct StakeInfo {
        uint usdAmount;
        uint blxAmount;
        uint burnedBlxAmount;
        uint lockDuration;
        uint unlockDate;
        int128 lockedBlxPrice;
        uint128 allowedWithdrawTime;
    }

    mapping(address => StakeInfo) public userStakes;
    mapping(address => uint) public userStakingLoss;
    mapping(address => uint) public totalStake;
    uint public stakerCount;

    uint public constant PCTS_USDC_NO_LOCK = 0;
    uint public constant PCTS_USDC_BLX_NO_LOCK = 1;
    uint public constant PCTS_USDC_MAX_LOCK = 2;
    uint public constant PCTS_USDC_BLX_MAX_LOCK = 3;
    uint public constant PCTS_MAX_VALUES = 3;

    uint[4] percents;
    
    // this together with the activeStakerList allows for round-robin distribution
    // so there would not be pro-long pile up of undistributed reward(which would flow through to blx staking/platform)
    uint public nextStakerToDisbribute; // for used by batch distribution
    uint public partialCount = 5; // how many to disbriute

    uint public lifetimeReward;
    uint public lifetimeLoss;
    uint public batchTimeReward;
    uint public accmulatedRewardBound = 100_000_000; // 100 USDC since last batch to force disbriution on reward arrival

    /// @dev get percents table column to check its correctness
    function getPercents(uint column)
    public view returns(uint userPercent)
    {
        userPercent = (
        percents[column]
        );
        //console.log("user percentage %d", userPercent);
    }

    constructor(address _trustedForwarder, address _usdToken, address _blxToken) ERC2771Context(_trustedForwarder)
    {
        // requires
        require(_usdToken != address(0), "SC:USDC_ZERO_ADDRESS");
        require(_blxToken != address(0), "SC:BLX_ZERO_ADDRESS");

        // interfaces
        USD = _usdToken;
        BLX = _blxToken;
        
        // constants
        minBlxAmount = 0; // just for now, it will be changed
        minUsdAmount = 0; // just for now, it will be changed

        require(PCT_BURN_DEFAULT < PCT_BASE, "SC:INVALID_INTERNAL_CONSTANTS");
        pctBurn = PCT_BURN_DEFAULT;

        _configurePercents();
    }

    /// @dev set partial distribute count
    function setPartialCount(uint _partialCount) public onlyOwner
    {
        require(_partialCount < 20, "SC:BATCH_COUNT_TOO_LARGE");
        partialCount = _partialCount;
    }

    /// @dev set accumulated bound before force distribution on reward arrival
    function setAccumlatedRewardBound(uint _bound) public onlyOwner
    {
        require((_bound == 0 || _bound >= 20_000_000) && _bound <= 200_000_000, "SC:INVALID_BOUND");
        accmulatedRewardBound = _bound;
    }

    /// @dev set min blx stake amount
    function setMinBlxAmount(uint amount) public onlyOwner
    {
        minBlxAmount = amount;
    }

    /// @dev set min usd stake amount
    function setMinUsdAmount(uint amount) public onlyOwner
    {
        minUsdAmount = amount;
    }

    /// @dev configures staking contract
    /// @param _priceOracle price oracle for blx|usd price rate
    /// @param _treasury treasury address
    /// @param _formulas formulas contract address
    function configure(
        address _priceOracle,
        address _treasury,
        address _formulas,
        address _stakingSnapshot,
        address _blxStaking
    ) external onlyOwner initializer
    {
        require(_formulas != address(0), "SC:FORMULAS_ZERO_ADDRESS");
        require(_priceOracle != address(0), "SC:ORACLE_ZERO_ADDRESS");
        require(_treasury != address(0), "SC:BLITZ_ZERO_ADDRESS");
        require(_stakingSnapshot != address(0), "SC:SNAPSHOT_ZERO_ADDRESS");
        require(_blxStaking != address(0), "SC:BLXSTAKING_ZERO_ADDRESS");

        priceOracle = IBlxOracle(_priceOracle);
        treasury = ITreasury(_treasury);
        formulas = IFormulas(_formulas);
        stakingSnapshot = IStakingSnapshot(_stakingSnapshot);
        blxStaking = IBlxStaking(_blxStaking);

        // configure underlying StakingRewards
        _configure(
            _treasury,       // rewards distribution
            IERC20(USD),    // rewards token
            IERC20(USD)    // staking token
        );
    }

    /// @return total usd stake
    function getTotalUsdStake()
        public view override returns (uint)
    {
        //console.log("total USD staked %d",totalStake[address(USD)]);
        return totalStake[address(USD)];
    }

    /// @dev returns true if user currently has locked funds, false otherwise
    function isLocked(address account)
    public view returns (bool)
    {
        StakeInfo memory info = userStakes[account];
        return
// lock state depends on position change, not time based        
//            info.unlockDate > block.timestamp &&
            info.lockDuration > 0;
    }

    function _linearizeSingle(
        uint y1, uint y2, uint duration
    ) internal pure returns (uint res)
    {
        res = y2 * duration;
        res += y1 * (MAX_LOCK_DURATION_WEEKS - duration);
        res = res / MAX_LOCK_DURATION_WEEKS;
        return res;
    }

    function _linearize(
        uint col1,
        uint col2,
        uint duration
    ) internal view returns (uint d)
    {
        require(duration <= MAX_LOCK_DURATION_WEEKS, "SC:INCONSISTENT_ARGS");

        (uint d1) = getPercents(col1);
        (uint d2) = getPercents(col2);

        d = _linearizeSingle(d1, d2, duration);
    }

    /// @dev returns percents of reward of all option types
    /// takes into account actual lock duration
    /// and calculates correct percent between max and min values
    function getUserPercents(address account)
        public view override returns
        (uint d)
    {
        StakeInfo memory stake = userStakes[account];
        //console.log("lock duration %d", stake.lockDuration);
        if (stake.blxAmount > 0 || stake.burnedBlxAmount > 0) {
            if (stake.lockDuration >= MAX_LOCK_DURATION_WEEKS)
                return getPercents(PCTS_USDC_BLX_MAX_LOCK);

            if (stake.lockDuration == 0)
                return getPercents(PCTS_USDC_BLX_NO_LOCK);

            return _linearize(
                PCTS_USDC_BLX_NO_LOCK,
                PCTS_USDC_BLX_MAX_LOCK,
                stake.lockDuration
            );
        }

        if (stake.lockDuration >= MAX_LOCK_DURATION_WEEKS)
            return getPercents(PCTS_USDC_MAX_LOCK);

        if (stake.lockDuration == 0)
            return getPercents(PCTS_USDC_NO_LOCK);

        return _linearize(
            PCTS_USDC_NO_LOCK,
            PCTS_USDC_MAX_LOCK,
            stake.lockDuration
        );
    }

    /// @dev locks user stake for duration weeks
    /// @param duration - week(s) to lock
    /// you can only lock if stake is not locked yet
    function lock(uint duration) external override
    {
        require(
            duration > 0 && duration <= MAX_LOCK_DURATION_WEEKS,
                "SC:INVALID_WEEKS_COUNT"
        );

        StakeInfo storage info = userStakes[_msgSender()];
        require(info.unlockDate <= block.timestamp, "SC:STAKE_LOCKED");

        info.lockDuration = duration;
        info.unlockDate = block.timestamp + duration * WEEK_PERIOD;
        //relock would reset burnt BLX
        info.burnedBlxAmount = 0;
        info.lockedBlxPrice = priceOracle.getBlxUsdRate();
        emit LockApplied(_msgSender(), duration);
    }

    /// @dev locks usd burning blx for increased payout
    function lockWithBurn(uint duration) external override
    {
        require(duration > 0 &&
            duration <= MAX_LOCK_DURATION_WEEKS,
            "SC:INVALID_WEEKS_COUNT"
        );

        address account = _msgSender();

        StakeInfo storage info = userStakes[account];
        uint blxAmount = info.blxAmount;
        require(info.unlockDate <= block.timestamp, "SC:STAKE_LOCKED");
        require(blxAmount > 0,"SC:NO_BLX");

        info.unlockDate = block.timestamp + duration * WEEK_PERIOD;
        info.lockDuration = duration;
        info.burnedBlxAmount = blxAmount;
        info.blxAmount = 0;
        // freeze blx price as per docs
        info.lockedBlxPrice = priceOracle.getBlxUsdRate();

        // burn all blx amount
        treasury.withdrawBlx(account, 0, blxAmount);

        emit LockApplied(account, duration);
    }

    /// @dev calculate current user payout
    function calculateUserPayout(
        address account,
        uint userProfit
    ) public virtual override view returns(uint payout)
    {
        uint p = getUserPercents(account);
        uint res = _partOf(p, userProfit, PCT_BASE);

        int128 res1 = calculatePayoutIncrease(account);
        res1 = res1.mul(res.toAbdk());
        //console.log("res %d", res);
        //console.log("res1 %d", res1.toUInt());

        return res + res1.toUInt();
    }

    /// @dev calculate payout increase
    function calculatePayoutIncrease(address account)
        public view returns(int128)
    {
        //int128 increase = Abdk._1; // general value
        int128 increase;
        // TODO: simplify!!!

        // blx impact
        {   // stack optimization
            // increase due to blx stake
            int128 stakeImpact = _calculateBlxStakeIncrease(account);
            stakeImpact = Abdk.min(stakeImpact, Abdk._0_5); // at max 0.5;

            // increase due to blx burn
            int128 burnImpact = _calculateBlxBurnIncrease(account);
            burnImpact = Abdk.min(burnImpact, Abdk._0_5);  // at max 0.5

            //increase = increase.add(Abdk.max(stakeImpact, burnImpact));
            increase = Abdk.max(stakeImpact, burnImpact);
        }

        // duration impact // disable for now until clear comments obtained
//        {
//            bool _locked = isLocked(account);
//
//            if (_locked) {
//                int128 durationImpact = userStakes[account].lockDuration.toAbdk();
//                durationImpact = durationImpact.div(MAX_LOCK_DURATION_WEEKS.toAbdk());
//
//                increase = increase.add(durationImpact);
//            }
//        }

        // increase is calculated

        return increase;
    }

    // ==================== INTERNAL ====================

    /// @dev calculates payout increase due to blx stake
    function _calculateBlxStakeIncrease(address account)
    internal view returns(int128)
    {
        StakeInfo memory info = userStakes[account];
        bool _locked = isLocked(account);

        // lock expired means zero duration
        uint duration = 0; // init is not necessary
        int128 rate; // when locked, rate is fixed
        if (_locked) {
            duration = info.lockDuration;
            rate = info.lockedBlxPrice;
        } else {
            rate = priceOracle.getBlxUsdRate();
        }
        // TODO: 
        // this means the rate is calculated at time of realization(position change) for
        // blx staking to total liquidity ratio, not time of staking
        int128 result = formulas.stakeBlxIncrease(
            info.blxAmount,             // blx amount
            rate,                       // blx rate
            totalStake[USD],            // total liquidity
            duration                    // lock duration
        );

        return result;
    }

    /// @dev calculates increase due to BLX burning
    function _calculateBlxBurnIncrease(address account)
        internal view returns(int128)
    {
        StakeInfo memory info = userStakes[account];

        bool _locked = isLocked(account);
        int128 rate; // when locked, rate is fixed
        if (_locked) {
            rate = info.lockedBlxPrice;
        } else {
            rate = priceOracle.getBlxUsdRate();
        }

        int128 result = formulas.burnBlxIncrease(
            info.burnedBlxAmount,   // blx amount
            rate,                  // blx rate
            totalStake[USD]         // total liquidity
        );

        return result;
    }

    /// @dev setup percents
    function _configurePercents() internal {
        /// baseline is 25%
        /// max USDC only is 50%
        /// max USDC only with BLX is 75% (50% @ 1.5x(max) due to BLX locking/burn)
        percents[PCTS_USDC_NO_LOCK]  = 2500;
        percents[PCTS_USDC_BLX_NO_LOCK] = 2500; // baseline the same as non-blx
        //percents[PCTS_USDC_BLX_NO_LOCK] = 3750; // not fixed but depending on BLX balance
        percents[PCTS_USDC_MAX_LOCK] = 5000;
        percents[PCTS_USDC_BLX_MAX_LOCK] = 5000; // baseline the same as non-blx
        //percents[PCTS_USDC_BLX_MAX_LOCK] = 7500; // not fixed but depending on BLX balance
    }

    /// @dev splits value amount to withdraw into user and tax value
    function _splitWithdrawal(uint value)
        internal view returns (uint toUser, uint toBurn)
    {
        toBurn = value * pctBurn / PCT_BASE;
        toUser = value - toBurn;
    }

    /// @dev deposit funds
    /// you can only deposit if no lock yet applied
    function deposit(uint usdAmount, uint blxAmount)
        external override
        nonReentrant
        whenNotPaused
    {
        require(!sunsetting, "SC:SUNSETTING");
        
        address sender = _msgSender();
        uint platformDeficit;
        uint currentUSDBalance;
        StakeInfo memory info = userStakes[sender];
        if (stakerCount == 0) {
            platformDeficit = treasury.platformIncome();
            currentUSDBalance = IERC20(USD).balanceOf(address(treasury));
            if (platformDeficit > currentUSDBalance) platformDeficit -= currentUSDBalance;
            else platformDeficit = 0;
            require(usdAmount > platformDeficit, "SC:NOT_ENOUGH_TO_COVER_PLATFORM_DEFICIT");
        }
        // cannot deposit while locked
        require(info.unlockDate <= block.timestamp, "SC:STAKE_LOCKED");

        if (partialCount > 0) {
            // if enabled, take part in maintain the pool
            // use try/catch so it would not affect normal operation
            try this.batchDistributeGainLoss(partialCount) {

            }
            catch {

            }
        }

        (uint reward, uint userReward, uint blxReward, uint platformReward, uint stakingLoss) = calcGainLossV2(sender);

        // net new balance
        uint newUsdAmount = (info.usdAmount >= stakingLoss ? info.usdAmount - stakingLoss : 0) + usdAmount + userReward;
        uint newBlxAmount = info.blxAmount + blxAmount;

        require(
            newUsdAmount >= minUsdAmount && newUsdAmount > 0,
            "SC:STABLE_MIN_AMOUNT_FAIL"
        );

        require(
            newBlxAmount == 0 || newUsdAmount > 0,
            "SC:CANNOT_STAKE_BLX_ONLY"
        );

        //USDC only is allowed
        require(newBlxAmount >= minBlxAmount || newBlxAmount == 0, "SC:BLX_MIN_AMOUNT_FAIL");

        if (usdAmount > 0) {
            treasury.takeTokensFrom(sender, usdAmount);
        }
        
        if (blxAmount > 0) {
            treasury.takeBlxFrom(sender, blxAmount);
        }

        if (blxReward > 0) {
            blxStaking.notifyRewardAmount(blxReward);
        }

        if (platformReward > 0) {
            processPlatformReward(platformReward);
        }

        if (stakingLoss > 0) {
            if (rewards[sender] > stakingLoss) {
                rewards[sender] -= stakingLoss;
            }
            else {
                rewards[sender] = 0;
            }
            // there is the remote possibility this is > staked amount due to rounding
            emit StakingLoss(sender, info.usdAmount > stakingLoss ? stakingLoss : info.usdAmount);
        }
        else if (userReward > 0) {
            // reward becomes staking
            rewards[sender] += userReward; // remember reward amount
            emit RewardStaked(sender, userReward);
        }
        // snapshot is recording gross reward, must reduce it to net user reward
        // this is equivalent to take out gross reward
        // calculate user portion and re-deposit those back
        // so there is a chance where new deposit < net taken out 
        int netDeposit = int(usdAmount) - int(reward - userReward);

        if (netDeposit > 0) {
            stakingSnapshot.increaseTotalUSDDeposits(uint(netDeposit));
            totalStake[USD] += uint(netDeposit);
            // TODO: is this needed ?
            _totalSupply += uint(netDeposit);
        }
        else if (netDeposit < 0) {
            stakingSnapshot.decreaseTotalUSDDeposits(uint(0 - netDeposit));
            totalStake[USD] -= uint(0 - netDeposit);
            // TODO: is this needed ?
            _totalSupply -= uint(0 -netDeposit);
        }
        
        userStakes[sender] = StakeInfo(
        {
            usdAmount:          newUsdAmount,
            blxAmount:          newBlxAmount,
            burnedBlxAmount:    0, // reset burnt amount on every deposit
            lockDuration:       0, // reset lock
            unlockDate:         0,
            lockedBlxPrice:     0,
            allowedWithdrawTime: uint128(block.timestamp) + LOCKED_TIME
        });
        
        // TODO: is this needed ?
        _balances[sender] = newUsdAmount;

        totalStake[BLX] += blxAmount;

        // must revise snapshot of depositor
        stakingSnapshot.updateDepositAndSnapshots(sender, newUsdAmount);

        
        // record new staker count(only there was no balance)
        if (info.usdAmount == 0) {
            // new record
            stakerCount += 1;
            addStaker(sender);
            emit NewStaker(sender, usdAmount, blxAmount);
        }
        emit StakeAdded(sender, usdAmount, blxAmount);

        if (platformDeficit > 0) {
            // we are here because this is the first deposit after all staker left
            // with remaining deficit(rare but possible in the case of american where trade loss eat into platform income/blx staking reward)
            // use deposit to cover them first
            //console.log("back pay platform income %d", platformDeficit);
            _notifyStakingLossAmount(platformDeficit);
        }
    }

    /// @dev withdraw all 
    /// helper function to make it easier to 'take everything'
    function withdrawAll() external
    {
        address sender = _msgSender();
        StakeInfo memory info = userStakes[sender];
        uint effectiveBalance = effectiveBalanceOf(sender);
        withdraw(effectiveBalance, info.blxAmount);
    }

    /// @dev withdraw funds only if no lock yet applied
    function withdraw(uint usdAmount, uint blxAmount)
        public override
        nonReentrant
    {
        address sender = _msgSender();
        StakeInfo memory info = userStakes[sender];

        require(sunsetting || (info.unlockDate <= block.timestamp && block.timestamp > info.allowedWithdrawTime), "SC:STAKE_LOCKED");

        if (partialCount > 0) {
            // if enabled, take part in maintain the pool
            // use try/catch so it would not affect normal operation
            try this.batchDistributeGainLoss(partialCount) {

            }
            catch {

            }
        }

        (uint reward, uint userReward, uint blxReward, uint platformReward, uint stakingLoss) = calcGainLossV2(sender);
        // there is the possibility that effectiveBalance < 0(if loss < stake due to rounding)
        // either user reward > 0 or stakingLoss > 0 but one of them would be zero
        int effectiveBalance = int(info.usdAmount) - int(stakingLoss) + int(userReward);
        
        require((effectiveBalance > 0 || stakingLoss == info.usdAmount) && uint(effectiveBalance) >= usdAmount, "SC:NOT_ENOUGH_STABLE_STAKE");
        require(info.blxAmount >= blxAmount, "SC:NOT_ENOUGH_BLX_STAKE");

        // net new balance, we are here only if effectiveBalance > 0 and >= usdAmount so ok to cast to uint
        uint newUsdAmount = uint(effectiveBalance) - usdAmount;
        uint newBlxAmount = info.blxAmount - blxAmount;

        require( // cannot leave BLX only
            newBlxAmount == 0 || newUsdAmount > 0,
            "SC:CANNOT_STAKE_BLX_ONLY"
        );
        require( // doesn't meet min BLX value requirement
            newBlxAmount == 0 || newBlxAmount >= minBlxAmount,
            "SC:BLX_MIN_AMOUNT_FAIL"
        );
        require(
            newUsdAmount >= minUsdAmount ||   // keep min amount
            newUsdAmount == 0,                   // or withdraw all
            "SC:STABLE_MIN_AMOUNT_FAIL"
        );

        if (blxReward > 0) {
            blxStaking.notifyRewardAmount(blxReward);
        }

        if (platformReward > 0) {
            processPlatformReward(platformReward);
        }

        // withdraw USD, after updating blx staking and platform reward portion
        // to reduce the chance of withdraw into locked collateral
        if (usdAmount > 0) {
            treasury.payTokensTo(sender, usdAmount);
        }


        if (stakingLoss > 0) {
            if (rewards[sender] > stakingLoss) {
                rewards[sender] -= stakingLoss;
            }
            else {
                rewards[sender] = 0;
            }
            // there is the remote possibility this is > staked amount due to rounding
            emit StakingLoss(sender, info.usdAmount > stakingLoss ? stakingLoss : info.usdAmount);
        }
        else if (userReward > 0) {
            // reward becomes staking
            rewards[sender] += userReward; // remember reward amount
            emit StakeAdded(sender, userReward, 0);
        }

        // update accrued 'claimable' reward
        // all withdrawal comes first from accrued reward
        if (usdAmount <= rewards[sender]) {
            rewards[sender] -= usdAmount;
        }
        else {
            rewards[sender] = 0;
        }

        // reward is gross, (reward - userReward) are excess that needs to be taken from the pool
        // equivalent to withdraw the gross reward then re-deposit userReward
        // userReward is always <= reward
        uint netWithdrawn = usdAmount + (reward - userReward);
        
        stakingSnapshot.decreaseTotalUSDDeposits(netWithdrawn);

        totalStake[USD] -= netWithdrawn;
        _totalSupply -= netWithdrawn;
        
        if (blxAmount > 0) {
            totalStake[BLX] -= blxAmount;
            // withdraw and burn predefined percent of tokens
            (uint toUser, uint toBurn) = _splitWithdrawal(blxAmount);
            treasury.withdrawBlx(_msgSender(), toUser, toBurn);
        }
        if (newUsdAmount > 0) {
            userStakes[sender] = StakeInfo({
                usdAmount:       newUsdAmount,
                blxAmount:       newBlxAmount,
                burnedBlxAmount: 0, // reset burnt amount
                lockDuration:    0, // reset lock
                unlockDate:      0,
                lockedBlxPrice:  0,
                allowedWithdrawTime: 0 // this only applies to initial deposit
            });

            //TODO: is this needed ?
            _balances[sender] = newUsdAmount;
        }
        else {
            // all removed, clearup reward etc.
            delete userStakes[sender];
            delete _balances[sender];
            if (rewards[sender] > 0) {
                // send out accrued rewards
                treasury.payTokensTo(sender, rewards[sender]);
                emit RewardPaid(sender, rewards[sender]);
            }
            delete rewards[sender];

            stakerCount -= 1;
            emit RemovedStaker(sender, usdAmount, blxAmount);

            address lastStaker = activeStakerList[activeStakerList.length - 1];
            if (lastStaker != sender) {
                try this.distributeGainLoss(lastStaker, false) {

                }
                catch {

                }
            }
            removeStaker(sender);
        }

        // must revise snapshot, even if newUsdAmount = 0
        stakingSnapshot.updateDepositAndSnapshots(sender, newUsdAmount);

        emit StakeWithdrawn(sender, usdAmount, blxAmount);
        
        if (stakerCount == 0) {
            // if there is no staker but still residual in snapshot, those are due to rounding
            // as sum(per depositor loss) > true loss
            // and 
            // sum(per deposit gain) < true gain
            // when calculating snapshots
            uint remaining = stakingSnapshot.totalUSDDeposits();
            if (remaining > 0) {
                processPlatformReward(remaining);
                // reduce to 0
                stakingSnapshot.decreaseTotalUSDDeposits(remaining);
            }
        }
    }

    /// @dev claim user reward from staking
    function claimReward(uint amount)
        public
        virtual
        override
    {
        address sender = _msgSender();

        if (partialCount > 0) {
            // if enabled, take part in maintain the pool
            // use try/catch so it would not affect normal operation
            try this.batchDistributeGainLoss(partialCount) {

            }
            catch {

            }
        }

        _distributeGainLoss(sender, true, true);
        uint accruedReward = rewards[sender];
        if (amount == 0) 
            amount = accruedReward;
        else 
            require(amount <= accruedReward, "SC:NOT_ENOUGH_REWARD");

        require(accruedReward > 0, "SC:NOTHING_TO_CLAIM");
        {
            // acccrued reward is part of the user stake balance
            userStakes[sender].usdAmount -= amount;
            _balances[sender] -= amount;
            rewards[sender] -= amount;
            treasury.payTokensTo(_msgSender(), amount);
            // pool balance reduced by claimed amount
            stakingSnapshot.decreaseTotalUSDDeposits(amount);
            totalStake[USD] -= amount;
            _totalSupply -= amount;

            emit RewardPaid(sender, amount);
        }
        // must revise snapshot
        stakingSnapshot.updateDepositAndSnapshots(sender, userStakes[sender].usdAmount);
    }

    function distributeGainLoss(address account, bool claim) 
        public  
        nonReentrant
    {
        _distributeGainLoss(account, claim, false);
    }
    /// @dev distribute user reward(thus calculate platform profit too)
    /// intended to be called by bot or third party
    /// if it is not user claiming
    /// this would change user staked amount if there is any pending rewards
    /// from deposit + reward => last deposit + userReward(recorded in the snapshot)
    /// thus reduce the portion after 
    function _distributeGainLoss(address account, bool claim, bool silent)
        internal
        returns (uint reward, uint userReward, uint blxReward, uint platformReward, uint stakingLoss)
    {
        (reward, userReward, blxReward, platformReward, stakingLoss) = calcGainLossV2(account);
        
        if (!silent) 
        {
            require(reward > 0 || stakingLoss > 0 || claim , "SC:NO_GAIN_LOSS");
        }

        require(account == _msgSender() || !claim, "SC:ONLY_USER_CAN_CLAIM");

        StakeInfo memory info = userStakes[account];

        if (blxReward > 0) {
            blxStaking.notifyRewardAmount(blxReward);
        }

        if (platformReward > 0) {
            processPlatformReward(platformReward);
        }

        if (stakingLoss > 0) {
            uint currentUsdAmount = info.usdAmount;
            int newUsdAmount = int(currentUsdAmount) - int(stakingLoss);
            userStakes[account].usdAmount = newUsdAmount < 0 ? 0 : uint(newUsdAmount);
            if (rewards[account] > stakingLoss) {
                rewards[account] -= stakingLoss;
            }
            else {
                rewards[account] = 0;
            }
            // there is the remote possibility this is > staked amount due to rounding
            emit StakingLoss(account, currentUsdAmount > stakingLoss ? stakingLoss : currentUsdAmount);
            // do not use cached version, used the revised version
            stakingSnapshot.updateDepositAndSnapshots(account, userStakes[account].usdAmount);
        }
        else if (userReward > 0) {
            // if not claiming, update balances otherwise leave it to caller
            uint excessStake = reward - userReward;
            // reward is gross, userReward is user portion
            // take out gross amount from the pool(record during reward gain from trading)
            // re-deposit userReward back
            stakingSnapshot.decreaseTotalUSDDeposits(excessStake);
            totalStake[USD] -= excessStake;
            _totalSupply -= excessStake;

            // if not claiming, move pending reward to staking
            userStakes[account].usdAmount += userReward;
            _balances[account] += userReward;
            rewards[account] += userReward;
            emit RewardStaked(account, userReward);
            // do not use cached version, used the revised version
            stakingSnapshot.updateDepositAndSnapshots(account, userStakes[account].usdAmount);
        }

        // if locked expired, reset lock state and burnt state
        // after payout is calculated
        // this means locked stake can enjoy increase payout after lock period
        // until there is action kick start calculation
        // external bot would be calling distriution periodically to calculate platform gain
        // but that may be after lock period
        // do this even if there is no change
        if (info.lockDuration > 0 && info.unlockDate <= block.timestamp) {
            //console.log("reset lock %o", account);
            userStakes[account].burnedBlxAmount = 0;
            userStakes[account].lockDuration = 0;
            userStakes[account].unlockDate = 0;
        }
    }

    //// @dev distribute some stakers pending reward/loss
    function batchDistributeGainLoss(uint count) public returns (uint rewards) {
        uint i;
        uint activeCount = activeStakerList.length;
        uint start = nextStakerToDisbribute;
        bool clearPlatformIncome;
        for (i = start; count > 0 && i < activeCount; i++)
        {
            address account = activeStakerList[i];
            // we don't want revert
            (uint reward, , , , ) = _distributeGainLoss(account, false, true);
            count -= 1;
            rewards += reward;
            if (!clearPlatformIncome) {
                clearPlatformIncome = (i > 0 && i % 5 == 0);
            }
        }
        if (i == activeCount) {
            nextStakerToDisbribute = 0;
        }
        else nextStakerToDisbribute = i;

        if (rewards > 10_000_000 
            || clearPlatformIncome
            ) {
            try treasury.distributePlatformIncome() {

            }
            catch {}
        }

        batchTimeReward = lifetimeReward;
    }
    
    function effectiveBalanceOf(address account)
        public
        view
        returns (uint256)
    {
        StakeInfo memory info = userStakes[account];
        
        if (info.usdAmount == 0) return 0;

        (, uint userReward, , , uint stakingLoss) = calcGainLossV2(account);
        if (stakingLoss > 0) {
            return info.usdAmount > stakingLoss ? info.usdAmount - stakingLoss : 0;
        }
        else {
            return info.usdAmount + userReward;
        }
    }

    function getAvailableReward(address account)
        public
        view
        returns (uint256 avaiableReward, uint256 pendingReward)
    {
        StakeInfo memory info = userStakes[account];
        
        if (info.usdAmount == 0) return (0,0);

        (, uint userReward, , , ) = calcGainLossV2(account);
        return (rewards[account] + userReward, userReward);
    }

    function notifyRewardAmount(uint digital, uint american, uint turbo)
        external
        virtual
        override
        onlyRewardsDistribution
    {
        profits.digital += digital;
        profits.american += american;
        profits.turbo += turbo;
        //console.log("digital reards %d", digital);
        //console.log("american reards %d", american);
        //console.log("turbo reards %d", turbo);
        //console.log("staked %d", totalStake[USD]);
        uint reward = digital + american + turbo;
        
        //reward = reward - rewardToBlx;
        if (stakerCount > 0) {
            // has stakers
            // staking pool increased
            totalStake[USD] += reward;
            // TODO: is this needed ?
            _totalSupply += (reward);
            stakingSnapshot.addReward(reward);
            emit RewardAdded(reward);
        }
        else {
            // no staker, everything goes to platform
            // this should never happen but just for completeness
            uint blxReward = address(blxStaking) != address(0) ?  _partOf(reward, PCT_BLX_PORTION, PCT_BASE) : 0;
            uint platformReward = reward - blxReward;
            if (blxReward > 0) {
                blxStaking.notifyRewardAmount(blxReward);
            }

            if (platformReward > 0) {
                processPlatformReward(platformReward);
            }
        }
        lifetimeReward += reward;

        if (lifetimeReward > accmulatedRewardBound + batchTimeReward && accmulatedRewardBound > 0) {
            // every 100 USDC increment, force partial distribution of 3
            try this.batchDistributeGainLoss(3) {

            }
            catch {}
        }
    }

    function notifyStakingLossAmount(uint amount)
        external
        virtual
        override
        onlyRewardsDistribution
    {
        _notifyStakingLossAmount(amount);
    }

    function _notifyStakingLossAmount(uint amount)
        internal
    {
        // if loss exceed staked amount, clip at that level
        uint netLoss = totalStake[USD] > amount ? amount : totalStake[USD];
        totalStake[USD] -= netLoss;
        _totalSupply -= netLoss;
        stakingSnapshot.addLoss(netLoss);
        emit LossAdded(netLoss);
        lifetimeLoss += amount;
    }

    // sunsetting - thus relax withdraw rule and disappear further staking
    function setSunsetting(bool isSunsetting)
    external onlyOwner
    {
        sunsetting = isSunsetting;
    }

    function processPlatformReward(uint reward) override internal {
        treasury.notifyPlatformReward(USD, reward);
    }

    // disable functions
    function _stake(address account, uint256 amount) external pure override {
        account;
        amount;
        revert("SC:DISABLED");
    }

    function _withdraw(address account, uint256 amount) external pure override {
        account;
        amount;
        revert("SC:DISABLED");
     }

    function _getReward(address account) external pure override {
        account;
        revert("SC:DISABLED");
    }

    function getEffectBalance(address _account) public view returns(uint) {
        return effectiveBalanceOf(_account);
        // StakeInfo memory info = userStakes[_account];
        // uint compoundedUSDDeposit = stakingSnapshot.getCompoundedUSDDeposit(_account);
        // uint reward = stakingSnapshot.getDepositorRewardGain(_account);
        // uint loss = info.usdAmount > compoundedUSDDeposit ? info.usdAmount - compoundedUSDDeposit : 0;
        // uint offset = loss > 0 && reward > 0 ? (reward > loss ? loss : reward) : 0;
        // return info.usdAmount - (loss - offset);
    }

    function calcGainLossV2(address _account) public view returns(uint reward, uint userReward, uint blxReward, uint platformReward, uint stakingLoss) {
        StakeInfo memory info = userStakes[_account];
        if (info.usdAmount == 0) return (0,0,0,0, info.usdAmount >  0 ? info.usdAmount : 0);
        
        uint compoundedUSDDeposit = stakingSnapshot.getCompoundedUSDDeposit(_account);
        reward = compoundedUSDDeposit > info.usdAmount ? compoundedUSDDeposit - info.usdAmount : 0;
        stakingLoss = compoundedUSDDeposit < info.usdAmount ? info.usdAmount - compoundedUSDDeposit : 0;

        userReward = reward > 0 ? calculateUserPayout(_account, reward) : 0;
        blxReward = address(blxStaking) != address(0) ? _partOf(reward, PCT_BLX_PORTION, PCT_BASE) : 0;
        // this should be true(as max user reward is only 75%) but just in case there is configuration error, clipped to remaining
        blxReward = blxReward <= reward - userReward ? blxReward : reward - userReward;
        platformReward = reward > userReward + blxReward ? reward - userReward - blxReward : 0;
        //console.log("staked %d", info.usdAmount);
        //console.log("compound deposit %d", compoundedUSDDeposit);
        //console.log("reward %d", reward);
        //console.log("userReward %d", userReward);
        //console.log("blxReward %d", blxReward);
        //console.log("platformReward %d", platformReward);
        //console.log("stakingLoss %d", stakingLoss);
    }
    
    ////@dev return list of staker and their non-realized reward
    ////(gross not what they would get which would be lower depending staking condition)
    ////this is mainly to assist external caller to save multiple calls
    function getActiveStakersPendingReward(uint from, uint count) external view returns (PendingReward[] memory pendingRewards)
    {
        address[] memory stakers = getActiveStakers(from, count);
        if (stakers.length > 0) {
            pendingRewards = new PendingReward[](stakers.length);
            for (uint256 index = 0; index < stakers.length; index++) {
                uint compoundedUSDDeposit = stakingSnapshot.getCompoundedUSDDeposit(stakers[index]);
                StakeInfo memory info = userStakes[stakers[index]];
                uint reward = compoundedUSDDeposit > info.usdAmount ? compoundedUSDDeposit - info.usdAmount : 0;
                pendingRewards[index] = (PendingReward(stakers[index], reward));
            }
        }
    }

    // Revise effective USD balance from gain/loss
    function _applyGainLoss(address _account) internal returns(uint offset, uint loss, uint reward) {
        StakeInfo memory info = userStakes[_account];
        if (totalStake[USD] == 0 || info.usdAmount == 0) return (0, 0, 0);
        
        uint compoundedUSDDeposit = stakingSnapshot.getCompoundedUSDDeposit(_account);
        reward = stakingSnapshot.getDepositorRewardGain(_account);
        loss = info.usdAmount > compoundedUSDDeposit ? info.usdAmount - compoundedUSDDeposit : 0;
        offset = loss > 0 && reward > 0 ? (reward > loss ? loss : reward) : 0;
        //console.log("offset %d", offset);
        //console.log("reward %d", reward);
        //console.log("loss %d", loss);
        reward -= offset;
        uint userReward = reward > 0 ? calculateUserPayout(_account, reward) : 0;
        uint platformReward = reward > userReward ? reward - userReward : 0;
        //console.log("deposit %d", info.usdAmount);
        //console.log("compoundedUSDDeposit %d", compoundedUSDDeposit);
        //console.log("user %d", userReward);
        //console.log("platform %d", platformReward);
        // by design, deposit can only go smaller(loss), reward is not recorded
        if (loss > 0) {
            uint netLoss = loss - offset;
            userStakes[_account].usdAmount -= netLoss;
            userStakingLoss[_account] += netLoss;
            emit StakingLoss(_account, netLoss);
        }

        if (userReward > 0) {
            rewards[_account] += userReward;
        }

        if (platformReward > 0) {
            // inform treasury about platfom reward
            processPlatformReward(platformReward);
        }
        // if locked expired, reset lock state and burnt state
        // after payout is calculated
        // this means locked stake can enjoy increase after lock period
        // until there is action kick start calculation
        // external bot would be calling distriution periodically to calculate platform gain
        // but that may be after lock period
        if (info.lockDuration > 0 && info.unlockDate <= block.timestamp) {
            userStakes[_account].burnedBlxAmount = 0;
            userStakes[_account].lockDuration = 0;
            userStakes[_account].unlockDate = 0;
        }
        // if (updateSnapshot) {
        //     // must revise snapshot
        //     stakingSnapshot.updateDepositAndSnapshots(_account, userStakes[_account].usdAmount);
        // }
    }

    /// @dev pick ERC2771Context over Ownable
    function _msgSender() internal view override(Context, ERC2771Context)
      returns (address sender) {
      sender = ERC2771Context._msgSender();
    }

    function _msgData() internal view override(Context, ERC2771Context)
      returns (bytes calldata) {
      return ERC2771Context._msgData();
    }

}

