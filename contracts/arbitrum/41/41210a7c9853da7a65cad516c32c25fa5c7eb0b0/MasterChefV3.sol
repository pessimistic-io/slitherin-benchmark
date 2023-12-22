// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IArbswapToken.sol";
import "./IVestingMaster.sol";

// The Contract is a fork of MasterChef by SushiSwap
// The biggest change made is using per second instead of per block for rewards
// This is due to Arbitrum extremely inconsistent block times
// The other biggest change was the removal of the migration functions
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once ARBS is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free.
contract MasterChefV3 is Ownable {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 boostAmount; // In order to give users higher reward
        uint256 rewardDebt; // Reward debt.
        uint256 lockStartTime;
        uint256 lockEndTime;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. ARBSs to distribute per block.
        uint256 lastRewardTime; // Last block time that ARBSs distribution occurs.
        uint256 accArbsPerShare; // Accumulated ARBSs per share, times 1e12. See below.
        bool lock;
        uint256 maxLockDuration;
        uint256 minLockDuration;
        uint256 durationFactor;
        uint256 boostWeight;
        uint256 boostAmount;
    }

    // Arbswap Token
    IArbswapToken public ARBS;

    IVestingMaster public Vesting;

    // Dev address.
    address public devaddr;
    // arbs tokens created per block.
    uint256 public arbsPerSecond;

    // set a max arbs per second, which can never be higher than 10 per second
    uint256 public constant maxArbsPerSecond = 100e18;

    uint256 public constant MaxAllocPoint = 40000000000000;

    uint256 public constant PRECISION = 1e12;

    uint256 public constant MAX_BOOST_WEIGHT = 50e12; // 5000%

    uint256 public constant MIN_BOOST_WEIGHT = 1e12; //100%

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Record whether pool is whitelist
    mapping(uint256 => bool) isWhitelistPool;
    // Record whether LP was added.
    mapping(address => bool) public LPTokenAdded;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block time when arbs mining starts.
    uint256 public immutable startTime;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event DepositLockPool(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        uint256 boostAmount,
        uint256 start,
        uint256 end
    );
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event NewVesting(address indexed vesting);
    event Harvest(address indexed user, uint256 pid, uint256 pending);
    event NewArbsPerSecond(uint256 arbsPerSecond);
    event NewWhitelist(uint256 pid, bool valid);

    constructor(
        IArbswapToken _arbs,
        address _devaddr,
        uint256 _arbsPerSecond,
        uint256 _startTime
    ) {
        ARBS = _arbs;
        devaddr = _devaddr;
        arbsPerSecond = _arbsPerSecond;
        startTime = _startTime;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function setVesting(address _vesting) external onlyOwner {
        // Vesing can be zero address when we do not need vesting.
        Vesting = IVestingMaster(_vesting);
        emit NewVesting(_vesting);
    }

    function setWhitelistPool(uint256 _pid, bool _isValid) external onlyOwner {
        isWhitelistPool[_pid] = _isValid;
        emit NewWhitelist(_pid, _isValid);
    }

    // Changes arbs token reward per second, with a cap of maxarbs per second
    // Good practice to update pools without messing up the contract
    function setArbsPerSecond(uint256 _arbsPerSecond, bool _withUpdate) external onlyOwner {
        require(_arbsPerSecond <= maxArbsPerSecond, "setArbsPerSecond: too many arbs!");

        // This MUST be done or pool rewards will be calculated with new arbs per second
        // This could unfairly punish small pools that dont have frequent deposits/withdraws/harvests
        if (_withUpdate) {
            massUpdatePools();
        }

        arbsPerSecond = _arbsPerSecond;
        emit NewArbsPerSecond(_arbsPerSecond);
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate,
        bool _lock,
        uint256 _maxLockDuration,
        uint256 _minLockDuration,
        uint256 _durationFactor,
        uint256 _boostWeight
    ) external onlyOwner {
        require(_allocPoint <= MaxAllocPoint, "add: too many alloc points!!");
        if (_lock) {
            require(
                _boostWeight >= MIN_BOOST_WEIGHT && _boostWeight <= MAX_BOOST_WEIGHT,
                "_boostWeight must be between MIN_BOOST_WEIGHT and MAX_BOOST_WEIGHT"
            );
            require(_minLockDuration > 0 && _maxLockDuration > _minLockDuration, "Invalid duration");
            require(_durationFactor > 0, "_durationFactor can not be zero");
        }

        // ensure you can not add duplicate pools
        require(!LPTokenAdded[address(_lpToken)], "Pool already exists!!!!");
        LPTokenAdded[address(_lpToken)] = true;

        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint += _allocPoint;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTime: lastRewardTime,
                accArbsPerShare: 0,
                lock: _lock,
                maxLockDuration: _maxLockDuration,
                minLockDuration: _minLockDuration,
                durationFactor: _durationFactor,
                boostWeight: _boostWeight,
                boostAmount: 0
            })
        );
    }

    // Update the given pool's ARBS allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyOwner {
        require(_allocPoint <= MaxAllocPoint, "add: too many alloc points!!");
        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function set(
        uint256 _pid,
        bool _withUpdate,
        uint256 _maxLockDuration,
        uint256 _minLockDuration,
        uint256 _durationFactor,
        uint256 _boostWeight
    ) external onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.lock, "Not lock pool");
        require(
            _boostWeight >= MIN_BOOST_WEIGHT && _boostWeight <= MAX_BOOST_WEIGHT,
            "_boostWeight must be between MIN_BOOST_WEIGHT and MAX_BOOST_WEIGHT"
        );
        require(_minLockDuration > 0 && _maxLockDuration > _minLockDuration, "Invalid duration");
        require(_durationFactor > 0, "_durationFactor can not be zero");
        if (_withUpdate) {
            massUpdatePools();
        }
        pool.maxLockDuration = _maxLockDuration;
        pool.minLockDuration = _minLockDuration;
        pool.durationFactor = _durationFactor;
        pool.boostWeight = _boostWeight;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        _from = _from > startTime ? _from : startTime;
        if (_to < startTime) {
            return 0;
        }
        return _to - _from;
    }

    // View function to see pending ARBSs on frontend.
    function pendingARBS(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accArbsPerShare = pool.accArbsPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (pool.lock) {
            lpSupply = pool.boostAmount;
        }
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 arbsReward = (multiplier * arbsPerSecond * (pool.allocPoint)) / totalAllocPoint;
            accArbsPerShare += (arbsReward * PRECISION) / lpSupply;
        }
        if (pool.lock) {
            return (user.boostAmount * accArbsPerShare) / PRECISION - user.rewardDebt;
        } else {
            return (user.amount * accArbsPerShare) / PRECISION - user.rewardDebt;
        }
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 arbsReward = (multiplier * arbsPerSecond * pool.allocPoint) / totalAllocPoint;

        ARBS.mintByLiquidityMining(devaddr, arbsReward / 10);
        ARBS.mintByLiquidityMining(address(this), arbsReward);
        if (pool.lock) {
            lpSupply = pool.boostAmount;
        }
        pool.accArbsPerShare += (arbsReward * PRECISION) / lpSupply;
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens to MasterChef flexiable pool for ARBS allocation.
    function depositFlexible(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(!pool.lock, "Lock pool");

        updatePool(_pid);

        uint256 pending = (user.amount * pool.accArbsPerShare) / PRECISION - user.rewardDebt;

        user.amount += _amount;
        user.rewardDebt = (user.amount * pool.accArbsPerShare) / PRECISION;

        if (pending > 0) {
            safeArbsTransfer(msg.sender, pending);
            emit Harvest(msg.sender, _pid, pending);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Deposit LP tokens to MasterChef lock pool for ARBS allocation.
    function depositLocked(
        uint256 _pid,
        uint256 _amount,
        uint256 _duration
    ) public {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.lock, "Not lock pool");
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount > 0) {
            require(_amount > 0 || _duration > 0, "_amount and _duration can not be zero at the same time");
        } else {
            require(_amount > 0 && _duration > 0, "_amount and _duration can not be zero");
        }

        updatePool(_pid);

        uint256 totalLockDuration = _duration;
        if (user.lockEndTime >= block.timestamp) {
            if (_amount > 0) {
                user.lockStartTime = block.timestamp;
            }
            totalLockDuration += user.lockEndTime - user.lockStartTime;
        } else {
            user.lockStartTime = block.timestamp;
        }
        if (totalLockDuration < pool.minLockDuration) {
            totalLockDuration = pool.minLockDuration;
        }
        if (totalLockDuration > pool.maxLockDuration) {
            totalLockDuration = pool.maxLockDuration;
        }
        user.lockEndTime = user.lockStartTime + totalLockDuration;

        uint256 pending = (user.boostAmount * pool.accArbsPerShare) / PRECISION - user.rewardDebt;
        pool.boostAmount -= user.boostAmount;
        user.amount += _amount;
        user.boostAmount = (user.amount * totalLockDuration * pool.boostWeight) / pool.durationFactor / PRECISION;
        user.rewardDebt = (user.boostAmount * pool.accArbsPerShare) / PRECISION;
        pool.boostAmount += user.boostAmount;

        if (pending > 0) {
            safeArbsTransfer(msg.sender, pending);
            emit Harvest(msg.sender, _pid, pending);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        emit DepositLockPool(msg.sender, _pid, _amount, user.boostAmount, user.lockStartTime, user.lockEndTime);
    }

    // Harvest Arbs from pool.
    function harvest(uint256 _pid) external {
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount > 0, "No LP");
        PoolInfo storage pool = poolInfo[_pid];
        updatePool(_pid);
        uint256 userReward;
        if (pool.lock) {
            userReward = (user.boostAmount * pool.accArbsPerShare) / PRECISION;
        } else {
            userReward = (user.amount * pool.accArbsPerShare) / PRECISION;
        }
        uint256 pending = userReward - user.rewardDebt;
        user.rewardDebt = userReward;

        if (pending > 0) {
            safeArbsTransfer(msg.sender, pending);
        }
        emit Harvest(msg.sender, _pid, pending);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (pool.lock) {
            require(user.lockEndTime < block.timestamp, "Still in lock");
        }
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);

        uint256 pending;
        if (pool.lock) {
            pending = (user.boostAmount * pool.accArbsPerShare) / PRECISION - user.rewardDebt;
            pool.boostAmount -= user.boostAmount;
        } else {
            pending = (user.amount * pool.accArbsPerShare) / PRECISION - user.rewardDebt;
        }

        user.amount -= _amount;
        if (pool.lock) {
            user.boostAmount = user.amount;
            pool.boostAmount += user.boostAmount;
            user.lockStartTime = 0;
            user.lockEndTime = 0;
        }
        user.rewardDebt = (user.amount * pool.accArbsPerShare) / PRECISION;

        if (pending > 0) {
            safeArbsTransfer(msg.sender, pending);
            emit Harvest(msg.sender, _pid, pending);
        }
        pool.lpToken.safeTransfer(address(msg.sender), _amount);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards, Only for whitelist pool. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        require(isWhitelistPool[_pid], "Not whitelist");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 withdrawAmount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        pool.lpToken.safeTransfer(address(msg.sender), withdrawAmount);
        emit EmergencyWithdraw(msg.sender, _pid, withdrawAmount);
    }

    // Safe arbs transfer function, just in case if rounding error causes pool to not have enough ARBSs.
    function safeArbsTransfer(address _to, uint256 _amount) internal {
        uint256 arbsBal = ARBS.balanceOf(address(this));
        uint256 amount = _amount;
        if (_amount > arbsBal) {
            amount = arbsBal;
        }
        if (address(Vesting) != address(0)) {
            IERC20(address(ARBS)).safeTransfer(address(Vesting), amount);
            Vesting.lock(msg.sender, amount);
        } else {
            IERC20(address(ARBS)).safeTransfer(_to, amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}

