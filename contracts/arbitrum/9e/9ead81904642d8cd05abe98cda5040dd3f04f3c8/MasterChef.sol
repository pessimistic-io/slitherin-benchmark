pragma solidity ^0.8.14;

// SPDX-License-Identifier: MIT

import "./Ownable.sol";
import "./ReentrancyGuard.sol";

import {IDarwinMasterChef, IERC20} from "./IMasterChef.sol";
import "./ITokenLocker.sol";
import "./IDarwin.sol";

import "./TokenLocker.sol";

/**
 * MasterChef is the master of Darwin. He makes Darwin and he is a fair guy.
 *
 * Note that it's ownable and the owner wields tremendous power. The ownership
 * will be transferred to a governance smart contract once DARWIN is sufficiently
 * distributed and the community can show to govern itself.
 *
 * Have fun reading it. Hopefully it's bug-free. God bless.
 */
contract DarwinMasterChef is IDarwinMasterChef, Ownable, ReentrancyGuard {

    // Darwin Protocol
    IERC20 public immutable darwin;
    // Dev
    address public immutable dev;
    // Token Locker
    ITokenLocker public immutable locker;
    // Darwin Max Supply
    uint256 public immutable maxSupply;
    // Darwin tokens created per second.
    uint256 public darwinPerSecond;
    // Deposit Fee address.
    address public feeAddress;

    // Max deposit fee: 4%.
    uint256 public constant MAX_DEPOSIT_FEE = 400;
    // Max deposit fee: 2%.
    uint256 public constant MAX_WITHDRAW_FEE = 200;
    // Max harvest interval: 2 days.
    uint256 public constant MAX_HARVEST_INTERVAL = 2 days;
    // Total locked up rewards.
    uint256 public totalLockedUpRewards;

    // Info of each pool.
    PoolInfo[] private _poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) private _userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The timestamp when DARWIN mining starts.
    uint256 public startTime;

    // Maximum darwinPerSecond: 1.
    uint256 public constant MAX_EMISSION_RATE = 1 ether;
    // Initial darwinPerSecond: 0.72.
    uint256 private constant _INITIAL_EMISSION_RATE = 0.72 ether;

    constructor(
        IERC20 _darwin,
        address _feeAddress,
        uint256 _startTime
    ){
        // Create TokenLocker contract
        bytes memory bytecode = type(TokenLocker).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(address(this)));
        address _locker;
        assembly {
            _locker := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        locker = ITokenLocker(_locker);

        darwin = _darwin;
        feeAddress = _feeAddress;
        startTime = _startTime;
        dev = msg.sender;
        darwinPerSecond = _INITIAL_EMISSION_RATE;
        maxSupply = IDarwin(address(darwin)).MAX_SUPPLY();
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // View function to gather the number of pools.
    function poolLength() external view returns (uint256) {
        return _poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function addPool(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, uint16 _withdrawFeeBP, uint256 _harvestInterval, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken){
        require(_depositFeeBP <= MAX_DEPOSIT_FEE, "addPool: invalid deposit fee basis points");
        require(_withdrawFeeBP <= MAX_WITHDRAW_FEE, "addPool: invalid withdraw fee basis points");
        require(_harvestInterval <= MAX_HARVEST_INTERVAL, "addPool: invalid harvest interval");

        _lpToken.balanceOf(address(this));
        poolExistence[_lpToken] = true;

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint + _allocPoint;

        _poolInfo.push(PoolInfo({
            lpToken : _lpToken,
            allocPoint : _allocPoint,
            lastRewardTime: lastRewardTime,
            accDarwinPerShare : 0,
            depositFeeBP : _depositFeeBP,
            withdrawFeeBP : _withdrawFeeBP,
            harvestInterval : _harvestInterval
        }));
    }


     // Update startTime by the owner (added this to ensure that dev can delay startTime due to congested network). Only used if required.
    function setStartTime(uint256 _newStartTime) external onlyOwner {
        require(startTime > block.timestamp, "setStartTime: farm already started");
        require(_newStartTime > block.timestamp, "setStartTime: new start time must be future time");

        uint256 _previousStartTime = startTime;

        startTime = _newStartTime;

        uint256 length = _poolInfo.length;
        for (uint256 pid = 0; pid < length; pid++) {
            PoolInfo storage pool = _poolInfo[pid];
            pool.lastRewardTime = startTime;
        }

        emit StartTimeChanged(_previousStartTime, _newStartTime);
    }

    // Update the given pool's DARWIN allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, uint16 _withdrawFeeBP, uint256 _harvestInterval, bool _withUpdate) external onlyOwner {
        require(_depositFeeBP <= MAX_DEPOSIT_FEE, "set: invalid deposit fee basis points");
        require(_withdrawFeeBP <= MAX_WITHDRAW_FEE, "set: invalid withdraw fee basis points");
        require(_harvestInterval <= MAX_HARVEST_INTERVAL, "set: invalid harvest interval");

        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint - _poolInfo[_pid].allocPoint + _allocPoint;
        _poolInfo[_pid].allocPoint = _allocPoint;
        _poolInfo[_pid].depositFeeBP = _depositFeeBP;
        _poolInfo[_pid].withdrawFeeBP = _withdrawFeeBP;
        _poolInfo[_pid].harvestInterval = _harvestInterval;
    }

    // Return reward multiplier over the given _from to _to timestamp.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to - _from;
    }

    // View function to see pending DARWINs on frontend.
    function pendingDarwin(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = _poolInfo[_pid];
        UserInfo storage user = _userInfo[_pid][_user];
        uint256 accDarwinPerShare = pool.accDarwinPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0 && totalAllocPoint > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 darwinReward = (multiplier * darwinPerSecond * pool.allocPoint) / totalAllocPoint;
            accDarwinPerShare = accDarwinPerShare + darwinReward * 1e18 / lpSupply;
        }

        uint256 pending = user.amount * accDarwinPerShare / 1e18 - user.rewardDebt;
        return pending + user.rewardLockedUp;
    }

    // View function to see if user can harvest Darwins's.
    function canHarvest(uint256 _pid, address _user) public view returns (bool) {
        UserInfo storage user = _userInfo[_pid][_user];
        return block.timestamp >= user.nextHarvestUntil;
    }

    // View function to see if user harvest until time.
    function getHarvestUntil(uint256 _pid, address _user) external view returns (uint256) {
        UserInfo storage user = _userInfo[_pid][_user];
        return user.nextHarvestUntil;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = _poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 darwinReward = multiplier * darwinPerSecond * pool.allocPoint / totalAllocPoint;

        if (darwin.totalSupply() >= maxSupply) {
            darwinReward = 0;
        } else if (darwin.totalSupply() + (darwinReward * 11 / 10) >= maxSupply) {
            darwinReward = maxSupply - (darwin.totalSupply() * 10 / 11);
        }

        if (darwinReward > 0) {
            darwin.mint(address(this), darwinReward);
            pool.accDarwinPerShare += darwinReward * 1e18 / lpSupply;
        }

        pool.lastRewardTime = block.timestamp;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = _poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Deposit LP tokens to MasterChef for DARWIN allocation.
    // Also usable (with _amount = 0) to increase the lock duration.
    function deposit(uint256 _pid, uint256 _amount, bool _lock, uint256 _lockDuration) public nonReentrant {
        PoolInfo storage pool = _poolInfo[_pid];
        UserInfo storage user = _userInfo[_pid][msg.sender];

        updatePool(_pid);
        _payOrLockupPendingDarwin(_pid);

        if (_amount > 0) {
            uint256 _balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.transferFrom(msg.sender, address(this), _amount);
            // for token that have transfer tax
            _amount = pool.lpToken.balanceOf(address(this)) - _balanceBefore;
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount * pool.depositFeeBP / 10000;
                pool.lpToken.transfer(feeAddress, depositFee);
                user.amount = user.amount + _amount - depositFee;
            } else {
                user.amount = user.amount + _amount;
            }
        }

        if (_lock) {
            locker.lockToken(msg.sender, address(pool.lpToken), _amount, _lockDuration);
            user.lockedAmount += _amount;
            user.lockEnd = locker.userLockedToken(msg.sender, address(pool.lpToken)).endTime;
        }

        user.rewardDebt = user.amount * pool.accDarwinPerShare / 1e18;
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Deposit LP tokens to MasterChef for DARWIN allocation. Not based on poolId but on the pool's LP token.
    function depositByLPToken(IERC20 lpToken, uint256 _amount, bool _lock, uint256 _lockDuration) external returns (bool) {
        for (uint i = 0; i < _poolInfo.length; i++) {
            if (_poolInfo[i].lpToken == lpToken) {
                deposit(i, _amount, _lock, _lockDuration);
                return true;
            }
        }
        return false;
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = _poolInfo[_pid];
        UserInfo storage user = _userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");

        // Prefer withdrawing already-in-masterchef tokens. If not enough, pick them (if unlocked) from TokenLocker.
        if (user.amount - user.lockedAmount < _amount) {
            uint amountToUnlock;
            if (_amount >= user.lockedAmount) {
                amountToUnlock = user.lockedAmount;
            } else {
                amountToUnlock = _amount;
            }
            locker.withdrawToken(msg.sender, address(pool.lpToken), amountToUnlock);
            user.lockedAmount -= amountToUnlock;
        }

        updatePool(_pid);
        _payOrLockupPendingDarwin(_pid);

        if (_amount > 0) {
            uint256 withdrawFee;
            if (pool.withdrawFeeBP > 0) {
                withdrawFee = _amount * pool.withdrawFeeBP / 10000;
                pool.lpToken.transfer(feeAddress, withdrawFee);
            } else {
                withdrawFee = 0;
            }
            pool.lpToken.transfer(msg.sender, _amount - withdrawFee);
            user.amount = user.amount - _amount;
        }

        user.rewardDebt = user.amount * pool.accDarwinPerShare / 1e18;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef. Not based on poolId but on the pool's LP token.
    function withdrawByLPToken(IERC20 lpToken, uint256 _amount) external returns (bool) {
        for (uint i = 0; i < _poolInfo.length; i++) {
            if (_poolInfo[i].lpToken == lpToken) {
                withdraw(i, _amount);
                return true;
            }
        }
        return false;
    }

    function _getPoolHarvestInterval(uint256 _pid) private view returns (uint256) {
        PoolInfo storage pool = _poolInfo[_pid];

        return block.timestamp + pool.harvestInterval;
    }

    // Pay or lockup pending darwin.
    function _payOrLockupPendingDarwin(uint256 _pid) private {
        PoolInfo storage pool = _poolInfo[_pid];
        UserInfo storage user = _userInfo[_pid][msg.sender];

        if (user.nextHarvestUntil == 0) {
            user.nextHarvestUntil = _getPoolHarvestInterval(_pid);
        }
        uint256 pending = user.amount * pool.accDarwinPerShare / 1e18 - user.rewardDebt;
        if (canHarvest(_pid, msg.sender)) {
            if (pending > 0 || user.rewardLockedUp > 0) {
                uint256 totalRewards = pending + user.rewardLockedUp;
                uint256 rewardsToLockup;
                uint256 rewardsToDistribute;
                rewardsToLockup = 0;
                rewardsToDistribute = totalRewards;
                // reset lockup
                totalLockedUpRewards = totalLockedUpRewards - user.rewardLockedUp + rewardsToLockup;
                user.rewardLockedUp = rewardsToLockup;
                user.nextHarvestUntil = _getPoolHarvestInterval(_pid);
                // send rewards
                _safeDarwinTransfer(msg.sender, rewardsToDistribute);
            }
        } else if (pending > 0) {
            user.rewardLockedUp += pending;
            totalLockedUpRewards += pending;
            emit RewardLockedUp(msg.sender, _pid, pending);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = _poolInfo[_pid];
        UserInfo storage user = _userInfo[_pid][msg.sender];
        require (user.amount > 0, "emergencyWithdraw: no amount to withdraw");
        uint256 withdrawFee = 0;
            if (pool.withdrawFeeBP > 0) {
                withdrawFee = user.amount * pool.withdrawFeeBP / 10000;
                pool.lpToken.transfer(feeAddress, withdrawFee);
            }
        pool.lpToken.transfer(msg.sender, user.amount - withdrawFee);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardLockedUp = 0;
        user.nextHarvestUntil = 0;
    }

    // Safe darwin transfer function, just in case if rounding error causes pool to not have enough DARWINs.
    function _safeDarwinTransfer(address _to, uint256 _amount) private {
        uint256 darwinBal = darwin.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > darwinBal) {
            transferSuccess = darwin.transfer(_to, darwinBal);
        } else {
            transferSuccess = darwin.transfer(_to, _amount);
        }
        require(transferSuccess, "safeDarwinTransfer: transfer failed");
    }

    // Update the address where deposit fees and half of king-rotating pools withdraw fees are sent (fee address).
    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0), "setFeeAddress: setting feeAddress to the zero address is forbidden");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    // Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _darwinPerSecond) external onlyOwner {
        require (_darwinPerSecond <= MAX_EMISSION_RATE, "updateEmissionRate: value higher than maximum");
        massUpdatePools();
        darwinPerSecond = _darwinPerSecond;
        emit UpdateEmissionRate(msg.sender, _darwinPerSecond);
    }

    function poolInfo() external view returns(PoolInfo[] memory) {
        return _poolInfo;
    }

    function userInfo(uint256 _pid, address _user) external view returns(UserInfo memory) {
        return _userInfo[_pid][_user];
    }
}
