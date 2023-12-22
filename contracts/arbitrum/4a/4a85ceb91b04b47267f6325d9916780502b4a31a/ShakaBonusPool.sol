// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./SafeMath.sol";
import "./EnumerableSet.sol";
import "./Ownable.sol";

contract ShakaBonusPool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
    }

    struct PoolInfo {
        IERC20 token; // Address of erc20 token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Tokens to distribute per second.
        uint256 totalDeposit;
        uint256 lastRewardTime; // Last timestamp that Tokens distribution occurs.
        uint256 accRewardsPerShare; // Accumulated RewardTokens per share, times 1e18.
    }

    struct PoolView {
        uint256 pid;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 rewardsPerSecond;
        uint256 accRewardPerShare;
        uint256 totalAmount;
        address token;
        string symbol;
        string name;
        uint8 decimals;
        uint256 startTime;
        uint256 bonusEndTime;
    }

    struct UserView {
        uint256 stakedAmount;
        uint256 unclaimedRewards;
        uint256 lpBalance;
    }

    IERC20 public rewardToken;
    uint256 public maxStakingPerUser;
    uint256 public rewardPerSecond;
    uint256 public standardRewardInterval = 3 days;

    uint256 public BONUS_MULTIPLIER = 1;

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 private totalAllocPoint = 0;
    uint256 public startTime;
    uint256 public bonusEndTime;
    EnumerableSet.AddressSet private _pairs;
    mapping(address => uint256) public LpOfPid;
    EnumerableSet.AddressSet private _callers;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount, uint256 rewards);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor() {
        rewardToken = IERC20(0xd9ae33E40270c51C4DcdBb23A4Bac0C8512542C2);
        rewardPerSecond = 1e18;
        startTime = block.timestamp;
        bonusEndTime = block.timestamp + 365 days;
        maxStakingPerUser = type(uint256).max;
    }

    function setStakeParams(
        IERC20 _rewardToken,
        uint256 _rewardPerSecond,
        uint256 _startTime,
        uint256 _bonusEndTime,
        uint256 _maxStakingPerUser
    ) external onlyOwner {
        rewardToken = _rewardToken;
        rewardPerSecond = _rewardPerSecond;
        startTime = _startTime;
        bonusEndTime = _bonusEndTime;
        maxStakingPerUser = _maxStakingPerUser;
    }

    function stopReward() public onlyOwner {
        bonusEndTime = block.timestamp;
    }

    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndTime) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndTime) {
            return 0;
        } else {
            return bonusEndTime.sub(_from).mul(BONUS_MULTIPLIER);
        }
    }

    function add(uint256 _allocPoint, address _token, bool _withUpdate) public onlyOwner {
        require(_token != address(0), "StakePool: _token is the zero address");

        require(!EnumerableSet.contains(_pairs, _token), "StakePool: _token is already added to the pool");
        EnumerableSet.add(_pairs, _token);

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({token: IERC20(_token), allocPoint: _allocPoint, totalDeposit: 0, lastRewardTime: lastRewardTime, accRewardsPerShare: 0}));
        LpOfPid[_token] = poolInfo.length - 1;
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        massUpdatePools();
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function setMaxStakingPerUser(uint256 amount) public onlyOwner {
        maxStakingPerUser = amount;
    }

    function setStandardRewardInterval(uint256 interval) public onlyOwner {
        require(interval > 0, "StakePool: interval must be greater than 0");
        standardRewardInterval = interval;
    }

    function pendingReward(uint256 _pid, address _user) public view returns (uint256) {
        require(_pid <= poolInfo.length - 1, "StakePool: Can not find this pool");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardsPerShare = pool.accRewardsPerShare;
        uint256 lpSupply = pool.totalDeposit;
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 tokenReward = multiplier.mul(rewardPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accRewardsPerShare = accRewardsPerShare.add(tokenReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accRewardsPerShare).div(1e18).sub(user.rewardDebt);
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.totalDeposit;
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 tokenReward = multiplier.mul(rewardPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accRewardsPerShare = pool.accRewardsPerShare.add(tokenReward.mul(1e18).div(lpSupply));
        pool.lastRewardTime = block.timestamp;
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        require(_pid <= poolInfo.length - 1, "StakePool: Can not find this pool");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(_amount.add(user.amount) <= maxStakingPerUser, "StakePool: exceed max stake");

        updatePool(_pid);

        uint256 reward;
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e18).sub(user.rewardDebt);
            if (pending > 0) {
                uint256 bal = rewardToken.balanceOf(address(this));
                if (bal >= pending) {
                    reward = pending;
                } else {
                    reward = bal;
                }
            }
        }

        if (_amount > 0) {
            uint256 oldBal = pool.token.balanceOf(address(this));
            pool.token.safeTransferFrom(address(msg.sender), address(this), _amount);
            _amount = pool.token.balanceOf(address(this)).sub(oldBal);

            user.amount = user.amount.add(_amount);
            pool.totalDeposit = pool.totalDeposit.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e18);

        if (reward > 0) {
            rewardToken.safeTransfer(address(msg.sender), reward);
        }

        emit Deposit(msg.sender, _amount);
    }

    function injectRewards(uint256 amount) public onlyCaller {
        _injectRewardsWithTime(amount, standardRewardInterval);
    }

    function injectRewardsWithTime(uint256 amount, uint256 rewardsSeconds) public onlyCaller {
        _injectRewardsWithTime(amount, rewardsSeconds);
    }

    function _injectRewardsWithTime(uint256 amount, uint256 rewardsSeconds) internal {
        massUpdatePools();

        uint256 oldBal = rewardToken.balanceOf(address(this));
        rewardToken.safeTransferFrom(_msgSender(), address(this), amount);
        uint256 realAmount = rewardToken.balanceOf(address(this)).sub(oldBal);

        uint256 remainingSeconds = bonusEndTime > block.timestamp ? bonusEndTime.sub(block.timestamp) : 0;
        uint256 remainingBal = rewardPerSecond.mul(remainingSeconds);

        if (remainingBal > 0) {
            rewardsSeconds = rewardsSeconds.add(remainingSeconds);
        }
        remainingBal = remainingBal.add(realAmount);

        rewardPerSecond = remainingBal.div(rewardsSeconds);

        if (block.timestamp >= startTime) {
            bonusEndTime = block.timestamp.add(rewardsSeconds);
        } else {
            bonusEndTime = startTime.add(rewardsSeconds);
        }
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "StakePool: Withdraw with insufficient balance");

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e18).sub(user.rewardDebt);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalDeposit = pool.totalDeposit.sub(_amount);
            pool.token.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e18);

        uint256 rewards;
        if (pending > 0) {
            uint256 bal = rewardToken.balanceOf(address(this));
            if (bal >= pending) {
                rewards = pending;
            } else {
                rewards = bal;
            }
        }
        rewardToken.safeTransfer(address(msg.sender), rewards);
        emit Withdraw(msg.sender, _amount, rewards);
    }

    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 amount = user.amount;

        if (pool.totalDeposit >= user.amount) {
            pool.totalDeposit = pool.totalDeposit.sub(user.amount);
        } else {
            pool.totalDeposit = 0;
        }
        user.amount = 0;
        user.rewardDebt = 0;

        pool.token.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    function emergencyRewardWithdraw(uint256 _amount) public onlyOwner {
        require(_amount <= rewardToken.balanceOf(address(this)), "StakePool: not enough token");
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

    function getPoolView(uint256 pid) public view returns (PoolView memory) {
        require(pid < poolInfo.length, "StakePool: pid out of range");
        PoolInfo memory pool = poolInfo[pid];
        IERC20Metadata token = IERC20Metadata(address(pool.token));
        uint256 rewardsPerSecond = pool.allocPoint.mul(rewardPerSecond).div(totalAllocPoint);
        return
            PoolView({
                pid: pid,
                allocPoint: pool.allocPoint,
                lastRewardTime: pool.lastRewardTime,
                accRewardPerShare: pool.accRewardsPerShare,
                rewardsPerSecond: rewardsPerSecond,
                totalAmount: pool.totalDeposit,
                token: address(token),
                symbol: token.symbol(),
                name: token.name(),
                decimals: token.decimals(),
                startTime: startTime,
                bonusEndTime: bonusEndTime
            });
    }

    function getAllPoolViews() external view returns (PoolView[] memory) {
        PoolView[] memory views = new PoolView[](poolInfo.length);
        for (uint256 i = 0; i < poolInfo.length; i++) {
            views[i] = getPoolView(i);
        }
        return views;
    }

    function getUserView(address token, address account) public view returns (UserView memory) {
        uint256 pid = LpOfPid[token];
        UserInfo memory user = userInfo[pid][account];
        uint256 unclaimedRewards = pendingReward(pid, account);
        uint256 lpBalance = IERC20(token).balanceOf(account);
        return UserView({stakedAmount: user.amount, unclaimedRewards: unclaimedRewards, lpBalance: lpBalance});
    }

    function getUserViews(address account) external view returns (UserView[] memory) {
        address token;
        UserView[] memory views = new UserView[](poolInfo.length);
        for (uint256 i = 0; i < poolInfo.length; i++) {
            token = address(poolInfo[i].token);
            views[i] = getUserView(token, account);
        }
        return views;
    }

    function addCaller(address val) public onlyOwner {
        require(val != address(0), "StakePool: val is the zero address");
        _callers.add(val);
    }

    function delCaller(address caller) public onlyOwner returns (bool) {
        require(caller != address(0), "StakePool: caller is the zero address");
        return _callers.remove(caller);
    }

    function getCallers() public view returns (address[] memory ret) {
        return _callers.values();
    }

    modifier onlyCaller() {
        require(_callers.contains(_msgSender()), "onlyCaller");
        _;
    }
}

