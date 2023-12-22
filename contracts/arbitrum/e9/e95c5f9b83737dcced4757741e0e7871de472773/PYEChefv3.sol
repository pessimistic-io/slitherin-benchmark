// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { EnumerableSet } from "./EnumerableSet.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { Ownable } from "./Ownable.sol";
import { IRewardToken } from "./IRewardToken.sol";
import { IMigratorChef } from "./IMigratorChef.sol";

contract PYEChefV3 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for IRewardToken;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 depositTime;    // The last time when the user deposit funds
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;          // Address of LP token contract.
        uint256 allocPoint;      // How many allocation points assigned to this pool. PYES to distribute per second.
        uint256 lastRewardTime; // Last timestamp that PYES distribution occurs.
        uint256 accPyesPerShare;  // Accumulated PYES per share, times 1e12. See below.
        uint256 lockTime;        // The time for lock funds
    }

    struct Multiplier {
        uint256 start;
        uint256 end;
        uint256 bonusMultiplier;
    }

    // The PYESwapToken TOKEN!
    IRewardToken public pyes;

    // Dev address.
    address public devAddr;

    // Dev fee.
    uint256 public devFee;

    // PYESwapToken tokens created per second.
    uint256 public pyesPerSecond;

    // PYESwapToken tokens created per day.
    uint256 public pyesPerDay;

    // Bonus mulipliers for early pyes makers.
    mapping (uint256 => Multiplier[]) public multiplierStages;

    // Number of Bonus muliplier stages.
    mapping (uint256 => uint256) public totalMultiplierStages;

    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;

    mapping (address => uint256) public earningsAwaitingStart;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    // The timestamp when PYESwapToken mining starts.
    uint256 public startTime;

    // The timestamp when PYESwapToken claiming starts.
    uint256 public claimStartTime;

    bool initialized;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);

    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    event DevFeeUpdated(address devFeeAddress, uint256 devFeeRate);

    event NewStartTime(uint256 startTime);

    event RewardRateUpdated(uint256 newRewardPerSecond, uint256 newRewardPerDay);

    event NewPoolAdded(
        uint256 indexed _pid, 
        address indexed lpToken, 
        uint256 lockTime, 
        uint256 bonusStartTime, 
        uint256 bonusEndTime, 
        uint256 poolAllocPoint, 
        uint256 newTotalAllocPoint
    );

    event PoolUpdated(
        uint256 indexed _pid, 
        address indexed lpToken, 
        uint256 lockTime, 
        uint256 poolAllocPoint, 
        uint256 newTotalAllocPoint
    );

    event MigratorSet(address migrator);

    event LPMigrated(
        uint256 indexed pid, 
        address newLpToken, 
        address oldLpToken, 
        uint256 lpMigrated
    );

    constructor (
        address _pyes,
        address _devAddr
    ) {
        _transferOwnership(_devAddr);
        pyes = IRewardToken(_pyes);
        devAddr = _devAddr;
    }

    function initialize(
        uint256 _pyesPerDay,
        uint256 _startTime,
        uint256 _claimStartTime
    ) external onlyOwner {
        require(!initialized, "Already initialized");
        pyesPerDay = _pyesPerDay;
        pyesPerSecond = _pyesPerDay / 86400;
        startTime = _startTime;
        claimStartTime = _claimStartTime;
        initialized = true;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint, 
        IERC20 _lpToken, 
        uint256 _lockTime, 
        uint256[] calldata _multiplierStart, 
        uint256[] calldata _multiplierRate, 
        uint256 _multiplierEnd, 
        bool _withUpdate
    ) external onlyOwner nonReentrant {
        require(initialized, "Not initialized");
        require(
            _multiplierStart.length == _multiplierRate.length && 
            _multiplierStart.length >= 1, 
            "Invalid Multipliers"
        );
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint += _allocPoint;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accPyesPerShare: 0,
            lockTime : _lockTime
        }));

        uint256 _pid = poolInfo.length - 1;
        uint256 length = _multiplierStart.length;
        totalMultiplierStages[_pid] = length;
        for (uint i = 0; i < length; i++) {
            require(
                _multiplierStart[i] < (i < length - 1 ? _multiplierStart[i + 1] : _multiplierEnd), 
                "Invalid start times"
            );
            multiplierStages[_pid].push(Multiplier({
                start: _multiplierStart[i],
                end: i < length - 1 ? _multiplierStart[i + 1] : _multiplierEnd,
                bonusMultiplier: _multiplierRate[i]
            }));
        }

        emit NewPoolAdded(
            _pid, 
            address(_lpToken), 
            _lockTime, 
            _multiplierStart[0], 
            _multiplierEnd, 
            _allocPoint, 
            totalAllocPoint
        );
    }

    // Update the given pool's PYESwapToken allocation point. Can only be called by the owner.
    function set(
        uint256 _pid, 
        uint256 _allocPoint, 
        uint256 _lockTime, 
        bool _withUpdate
    ) external onlyOwner nonReentrant {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].lockTime = _lockTime;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint - prevAllocPoint + _allocPoint;
        }
        emit PoolUpdated(_pid, address(poolInfo[_pid].lpToken), _lockTime, _allocPoint, totalAllocPoint);
    }

    function updateMultipliers(
        uint256 _pid, 
        uint256[] calldata _multiplierStart, 
        uint256[] calldata _multiplierRate, 
        uint256 _multiplierEnd
    ) external onlyOwner {
        require(_multiplierStart.length == _multiplierRate.length, "Length mismatch");
        uint256 length = _multiplierStart.length;
        totalMultiplierStages[_pid] = length;
        for (uint i = 0; i < length; i++) {
            require(
                _multiplierStart[i] < (i < length - 1 ? _multiplierStart[i + 1] : _multiplierEnd),
                "Invalid start times"
            );
            multiplierStages[_pid][i].start = _multiplierStart[i];
            multiplierStages[_pid][i].end = i < length - 1 ? _multiplierStart[i + 1] : _multiplierEnd;
            multiplierStages[_pid][i].bonusMultiplier = _multiplierRate[i];
        }
    }

    // Deposit LP tokens to MasterChef for PYESwapToken allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = ((user.amount * pool.accPyesPerShare) / 1e12) - user.rewardDebt;
            if (pending > 0) {
                if (block.timestamp > claimStartTime) {
                    if (earningsAwaitingStart[msg.sender] > 0) {
                        pending += earningsAwaitingStart[msg.sender];
                        delete earningsAwaitingStart[msg.sender];
                    }
                    safePyesTransfer(msg.sender, pending);
                } else {
                    earningsAwaitingStart[msg.sender] += pending;
                }
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.depositTime = block.timestamp;
            user.amount += _amount;
        }
        user.rewardDebt = (user.amount * pool.accPyesPerShare) / 1e12;
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        require(user.depositTime + pool.lockTime < block.timestamp, "Can not withdraw in lock period");

        updatePool(_pid);
        uint256 pending = ((user.amount * pool.accPyesPerShare) / 1e12) - user.rewardDebt;
        if (pending > 0) {
            if (block.timestamp > claimStartTime) {
                if (earningsAwaitingStart[msg.sender] > 0) {
                    pending += earningsAwaitingStart[msg.sender];
                    delete earningsAwaitingStart[msg.sender];
                }
                safePyesTransfer(msg.sender, pending);
            } else {
                earningsAwaitingStart[msg.sender] += pending;
            }
        }
        if(_amount > 0) {
            user.amount -= _amount;
            pool.lpToken.safeTransfer(msg.sender, _amount);
        }
        user.rewardDebt = (user.amount * pool.accPyesPerShare) / 1e12;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function claimEarningsAwatingStart() external nonReentrant {
        require(block.timestamp > claimStartTime, "Claim start time not reached");
        uint256 pending = earningsAwaitingStart[msg.sender];
        if (pending > 0) {
            delete earningsAwaitingStart[msg.sender];
            safePyesTransfer(msg.sender, pending);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    function updatePyesRewardRate(uint256 _pyesPerDay) external onlyOwner {
        uint256 _pyesPerSecond = _pyesPerDay / 86400;
        pyesPerDay = _pyesPerDay;
        pyesPerSecond = _pyesPerSecond;
        emit RewardRateUpdated(_pyesPerSecond, _pyesPerDay);
    }

    /**
     * @notice It allows the admin to update start time
     * @dev This function is only callable by owner.
     * @param _startTime: the new start timestamp
     */
    function updateStartTime(uint256 _startTime) external onlyOwner {
        require(block.timestamp < _startTime, "startTime must be higher than now");

        startTime = _startTime;

        // Set the lastRewardTime for all pools as the startTime
        massUpdatePoolsStart();

        emit NewStartTime(_startTime);
    }

    function updateClaimStart(uint256 _claimStartTime) external onlyOwner {
        require(block.timestamp < claimStartTime, "Claim already started");
        claimStartTime = _claimStartTime;
    }

    // Update dev address by the previous dev.
    function updateDev(address _devAddr, uint256 _devFee) external onlyOwner {
        devAddr = _devAddr;
        devFee = _devFee;
        emit DevFeeUpdated(_devAddr, _devFee);
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) external onlyOwner {
        migrator = _migrator;
        emit MigratorSet(address(_migrator));
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) external {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = IERC20(migrator.migrate(address(lpToken)));
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;

        emit LPMigrated(_pid, address(newLpToken), address(lpToken), bal);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // View function to see pending PYES on frontend.
    function pendingPyes(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPyesPerShare = pool.accPyesPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(_pid, pool.lastRewardTime, block.timestamp);
            uint256 pyesReward = (multiplier * pyesPerSecond * pool.allocPoint) / totalAllocPoint;
            accPyesPerShare += (pyesReward * 1e12) / lpSupply;
        }
        return ((user.amount * accPyesPerShare) / 1e12) - user.rewardDebt;
    }

    function getCurrentMultiplier(uint256 _pid) external view returns (uint256) {
        if (block.timestamp > multiplierStages[_pid][totalMultiplierStages[_pid] - 1].end) {
            return 10000;
        }

        for (uint i = 0; i < totalMultiplierStages[_pid]; i++) {
            if (block.timestamp >= multiplierStages[_pid][i].start) {
                if (block.timestamp <= multiplierStages[_pid][i].end) {
                    return multiplierStages[_pid][i].bonusMultiplier;
                } else {
                    continue;
                }
            } else {
                break;
            }
        }
        return 10000;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() internal {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePoolsStart() internal {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePoolStart(pid);
        }
    }

    // Safe pyes transfer function, just in case if rounding error causes pool to not have enough PYESs.
    function safePyesTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBalance = pyes.balanceOf(address(this));
        pyes.safeTransfer(_to, _amount > tokenBalance ? tokenBalance : _amount);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(_pid, pool.lastRewardTime, block.timestamp);
        uint256 pyesReward = (multiplier * pyesPerSecond * pool.allocPoint) / totalAllocPoint;
        if (devFee > 0) { pyes.mint(devAddr, ((pyesReward * devFee) / 10000)); }
        pyes.mint(address(this), pyesReward);
        pool.accPyesPerShare += (pyesReward * 1e12) / lpSupply;
        pool.lastRewardTime = block.timestamp;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePoolStart(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        pool.lastRewardTime = block.timestamp;
    }

    function getMultiplier(uint256 _pid, uint256 _from, uint256 _to) internal view returns (uint256 multiplier) {
        if (_from > multiplierStages[_pid][totalMultiplierStages[_pid] - 1].end) {
            return (_to - _from);
        }

        for (uint i = 0; i < totalMultiplierStages[_pid]; i++) {
            if (_from >= multiplierStages[_pid][i].start && _from <= multiplierStages[_pid][i].end) {
                if (_to <= multiplierStages[_pid][i].end) {
                    multiplier += ((_to - _from) * multiplierStages[_pid][i].bonusMultiplier) / 10000;
                    break;
                } else {
                    multiplier += 
                        ((multiplierStages[_pid][i].end - _from) * multiplierStages[_pid][i].bonusMultiplier) / 10000;
                    _from = multiplierStages[_pid][i].end;
                    continue;
                }
            } else {
                continue;
            }
        }
        if (_to > _from) { multiplier += (_to - _from); }
    }
}
