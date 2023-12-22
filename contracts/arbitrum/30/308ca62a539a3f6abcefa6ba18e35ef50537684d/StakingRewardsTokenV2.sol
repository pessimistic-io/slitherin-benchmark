// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./ERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./LodestarChef.sol";

contract StakingRewardsTokenV2 is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    Ownable2StepUpgradeable,
    ERC20Upgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Stake {
        uint256 amount;
        uint256 startTimestamp;
        uint256 alreadyConverted;
    }
    //comment

    struct StakingInfo {
        uint256 lodeAmount;
        uint256 stLODEAmount;
        uint256 startTime;
        uint256 lockTime;
        uint256 relockStLODEAmount;
        uint256 nextStakeId;
        uint256 totalEsLODEStakedByUser;
        uint256 lastClaimTime;
    }

    mapping(address => Stake[]) public esLODEStakes;

    mapping(address => StakingInfo) public stakers;

    IERC20Upgradeable public LODE;
    IERC20Upgradeable public WETH;
    IERC20Upgradeable public esLODE;

    uint256 public weeklyRewards;
    uint256 public lastUpdateTimestamp;
    uint256 public totalStaked;
    uint256 public totalRelockStLODE;
    uint256 public stLODE3M;
    uint256 public stLODE6M;
    uint256 public vstLODE3M;
    uint256 public vstLODE6M;

    bool public lockCanceled;
    bool public withdrawEsLODEAllowed;
    address public routerContract;

    uint256 public constant BASE = 1e18;
    uint256 public totalEsLODEStaked;

    //chef

    uint256 private constant MUL_CONSTANT = 1e14;
    IERC20Upgradeable public stakingToken;
    IERC20Upgradeable public pls;

    struct UserInfo {
        uint96 amount; // Staking tokens the user has provided
        int128 wethRewardsDebt;
    }

    uint256 public wethPerSecond;
    uint128 public accWethPerShare;
    uint96 public shares; // total staked,TODO:WAS PRIVATE PRIOR TO TESTING
    uint32 public lastRewardSecond;

    mapping(address => UserInfo) public userInfo;

    error DEPOSIT_ERROR();
    error WITHDRAW_ERROR();
    error UNAUTHORIZED();

    event Deposit(address indexed _user, uint256 _amount);
    event Withdraw(address indexed _user, uint256 _amount);
    event Harvest(address indexed _user, uint256 _amount);
    event EmergencyWithdraw(address indexed _user, uint256 _amount);

    //end chef

    uint256[49] private __gap;

    event StakedLODE(address indexed user, uint256 amount, uint256 lockTime);
    event StakedEsLODE(address indexed user, uint256 amount);
    event UnstakedLODE(address indexed user, uint256 amount);
    event UnstakedEsLODE(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 reward);
    event StakingLockedCanceled();
    event WeeklyRewardsUpdated(uint256 newRewards);
    event StakingRatesUpdated(uint256 stLODE3M, uint256 stLODE6M, uint256 vstLODE3M, uint256 vstLODE6M);
    event StakingPaused();
    event StakingUnpaused();
    event RouterContractUpdated(address newRouterContract);
    event esLODEUnlocked(bool state, uint256 timestamp);
    event Relocked(address user, uint256 lockTime);

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

        WETH.approve(address(this), type(uint256).max);

        stLODE3M = 1400000000000000000;
        stLODE6M = 2000000000000000000;
        vstLODE3M = 50000000000000000;
        vstLODE6M = 100000000000000000;

        lastRewardSecond = uint32(block.timestamp);
    }

    function stakeLODE(uint256 amount, uint256 lockTime) external whenNotPaused nonReentrant {
        require(amount != 0, "StakingRewards: Invalid stake amount");
        require(
            lockTime == 10 seconds || lockTime == 90 days || lockTime == 180 days,
            "StakingRewards: Invalid lock time"
        );
        uint256 currentLockTime = stakers[msg.sender].lockTime;
        uint256 currentTime = block.timestamp;
        uint256 unlockTime = currentTime + currentLockTime;

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

    function convertEsLODEToLODE(address user) public {
        //since this is also called on unstake and harvesting, we exit out of this function if user has no esLODE staked.
        if (stakers[msg.sender].totalEsLODEStakedByUser == 0) {
            return;
        }

        uint256 lockTime = stakers[user].lockTime;
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
                    stLODEAdjustment += (conversionAmount * (stLODE3M - 1e18)) / BASE;
                } else if (lockTime == 180 days) {
                    stLODEAdjustment += (conversionAmount * (stLODE6M - 1e18)) / BASE;
                }
            } else if (timeDiff < totalDays) {
                uint256 conversionRatioMantissa = (timeDiff * BASE) / totalDays;
                conversionAmount = ((userStakes[i].amount * conversionRatioMantissa) / BASE) - alreadyConverted;
                amountToTransfer += conversionAmount;
                alreadyConverted += conversionAmount;
                userStakes[i].amount -= conversionAmount;
                if (lockTime == 90 days) {
                    stLODEAdjustment += (conversionAmount * (stLODE3M - 1e18)) / BASE;
                } else if (lockTime == 180 days) {
                    stLODEAdjustment += (conversionAmount * (stLODE6M - 1e18)) / BASE;
                }
            }
        }
        if (stLODEAdjustment != 0) {
            stakers[user].stLODEAmount += stLODEAdjustment;
        }
        stakers[user].lodeAmount += amountToTransfer;
        stakers[user].totalEsLODEStakedByUser -= amountToTransfer;

        if (stLODEAdjustment != 0) {
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
    }

    function relock(uint256 lockTime) external whenNotPaused nonReentrant {
        require(lockTime == 90 days || lockTime == 180 days, "StakingRewards: Invalid lock time");
        StakingInfo storage info = stakers[msg.sender];
        require(info.lodeAmount > 0, "StakingRewards: No stake found");
        require(info.startTime + info.lockTime <= block.timestamp, "StakingRewards: Lock time not expired");

        convertEsLODEToLODE(msg.sender);

        // Calculate vstLODE to mint based on the previous lock period
        uint256 stakeAmount;
        if (info.lockTime == 90 days) {
            stakeAmount = (info.lodeAmount * vstLODE3M) / 1e18;
        } else if (info.lockTime == 180 days) {
            stakeAmount = (info.lodeAmount * vstLODE6M) / 1e18;
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
        } else {
            uint256 newStakedBalance = stakedBalance - amount;
            uint256 newStLODEBalance = newStakedBalance + esLODEBalance;
            stLODEReduction = stLODEBalance - newStLODEBalance;
            require(stLODEReduction <= stLODEBalance, "StakingRewards: Invalid unstake amount");
            stakers[staker].stLODEAmount = newStLODEBalance;
            stakers[staker].lockTime = 10 seconds;
            stakers[staker].startTime = block.timestamp;
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

    function withdrawEsLODE() external nonReentrant {
        require(withdrawEsLODEAllowed == true, "esLODE Withdrawals Not Permitted");
        //harvest();
        StakingInfo storage account = stakers[msg.sender];
        uint256 totalEsLODE = account.totalEsLODEStakedByUser;
        esLODE.safeTransfer(msg.sender, totalEsLODE);
    }

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

    function rewardPerShare(uint256 _rewardRatePerSecond) public view returns (uint128) {
        // duration = block.timestamp - lastRewardSecond;
        // tokenReward = duration * _rewardRatePerSecond;
        // tokenRewardPerShare = (tokenReward * MUL_CONSTANT) / shares;

        unchecked {
            return uint128(((block.timestamp - lastRewardSecond) * _rewardRatePerSecond * MUL_CONSTANT) / shares);
        }
    }

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
        if (msg.sender == owner()) {
            wethPerSecond = _wethPerSecond;
        } else {
            revert UNAUTHORIZED();
        }
    }

    function calculateWethPerSecond(uint256 rewardsAmount) public pure returns (uint256 _wethPerSecond) {
        uint256 periodDuration = 7 days;
        _wethPerSecond = rewardsAmount / periodDuration;
    }

    function updateWeeklyRewards(uint256 _weeklyRewards) external {
        require(msg.sender == routerContract, "StakingRewards: Unauthorized");
        weeklyRewards = _weeklyRewards;
        lastUpdateTimestamp = block.timestamp;
        setStartTime(uint32(block.timestamp));
        uint256 _wethPerSecond = calculateWethPerSecond(_weeklyRewards);
        setEmission(_wethPerSecond);
        emit WeeklyRewardsUpdated(_weeklyRewards);
    }

    function claimRewards() external nonReentrant {
        require(msg.sender != address(0), "Invalid Address");
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

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _safeTokenTransfer(IERC20Upgradeable _token, address _to, uint256 _amount) internal {
        uint256 bal = _token.balanceOf(address(this));

        if (_amount > bal) {
            _token.transfer(_to, bal);
        } else {
            _token.transfer(_to, _amount);
        }
    }

    // Helper function to calculate the vote share of a user
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

    function _pauseStaking() external onlyOwner {
        _pause();
        emit StakingPaused();
    }

    function _unpauseStaking() external onlyOwner {
        _unpause();
        emit StakingUnpaused();
    }

    function _updateRouterContract(address _routerContract) external onlyOwner {
        routerContract = _routerContract;
        emit RouterContractUpdated(_routerContract);
    }

    function _allowEsLODEWithdraw(bool state) external onlyOwner {
        withdrawEsLODEAllowed = state;
        emit esLODEUnlocked(state, block.timestamp);
    }

    function blockTime() public view returns (uint256) {
        return block.timestamp;
    }
}

