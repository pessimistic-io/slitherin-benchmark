// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./ICauldronV4.sol";
import "./Math.sol";
import "./IMasterChef.sol";

// MasterChef is the master of Cake. He can make Cake and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once CAKE is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable, IMasterChef {
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // Info of each pool.
    struct PoolInfo {
        address stakeToken;
        address rewardToken;
        uint256 lastRewardTimestamp;
        uint256 rewardPerSecond;
        uint256 rewardPerShare; //multiply 1e20
        bool isInspire;
    }

    uint256 public arvLastRelease;
    uint256 public arvCirculatingSupply;
    uint256 public totalVinLock;
    mapping(uint256 => uint256) public totalStake;
    mapping(address => LockDetail[]) public userLock;
    mapping(address => uint256) public userUnlockIndex;
    IStrictERC20 public arv;
    IStrictERC20 public inToken;
    IStrictERC20 public vin;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    mapping(address => uint256) public cauldronPoolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => VestingInfo[]) public userVestingInfo;
    mapping(address => uint256) public userVestingIndex;
    mapping(address => uint256) public userPendingReward;

    uint256 public constant LOCK_POOL = 0;
    uint256 public constant VIN_POOL = 1;
    uint256 public constant ARV_POOL = 2;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(address _arv, address _vin, address _in, uint256 startTimestamp) {
        arv = IStrictERC20(_arv);
        vin = IStrictERC20(_vin);
        inToken = IStrictERC20(_in);
        arvLastRelease = block.timestamp - (block.timestamp % 1 days) + 1 days;
        // staking pool
        poolInfo.push(
            PoolInfo({
                stakeToken: address(0),
                rewardToken: address(0),
                lastRewardTimestamp: block.timestamp - (block.timestamp % 1 days) + 1 days,
                rewardPerSecond: uint256(100 ether) / 1 days,
                rewardPerShare: 0,
                isInspire: false
            })
        );
        poolInfo.push(
            PoolInfo({
                stakeToken: _vin,
                rewardToken: _in,
                lastRewardTimestamp: startTimestamp,
                rewardPerSecond: 0,
                rewardPerShare: 0,
                isInspire: false
            })
        );
        poolInfo.push(
            PoolInfo({
                stakeToken: _arv,
                rewardToken: _in,
                lastRewardTimestamp: startTimestamp,
                rewardPerSecond: 0,
                rewardPerShare: 0,
                isInspire: false
            })
        );
    }

    function addRewardToPool(uint256 amount) public {
        uint256 totalStake1 = totalStake[1];
        uint256 totalStake2 = totalStake[2];
        IStrictERC20 reward = IStrictERC20(inToken);
        reward.transferFrom(msg.sender, address(this), amount);
        if (totalStake1 > 0 && totalStake2 > 0) {
            poolInfo[1].rewardPerShare += ((amount - (amount / 6)) * 1e20) / totalStake1;
            poolInfo[2].rewardPerShare += ((amount / 6) * 1e20) / totalStake2;
        } else if (totalStake1 > 0) {
            //50% distribute to the vin stakers
            poolInfo[1].rewardPerShare += (amount * 1e20) / totalStake1;
        } else if (totalStake2 > 0) {
            //20% of 50% tresury income distribute to the arv stakers
            poolInfo[2].rewardPerShare += (amount * 1e20) / totalStake2;
        }
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function addPool(uint256 _rewardPerSecond, address _stakeToken, uint256 startTimestamp, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        poolInfo.push(
            PoolInfo({
                stakeToken: _stakeToken,
                rewardToken: address(vin),
                lastRewardTimestamp: startTimestamp,
                rewardPerSecond: _rewardPerSecond,
                rewardPerShare: 0,
                isInspire: false
            })
        );
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function addInspire(uint256 _rewardPerSecond, address _cauldronAddress, uint256 startTimestamp, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        cauldronPoolInfo[_cauldronAddress] = poolInfo.length;
        poolInfo.push(
            PoolInfo({
                stakeToken: _cauldronAddress,
                rewardToken: address(vin),
                lastRewardTimestamp: startTimestamp,
                rewardPerSecond: _rewardPerSecond,
                rewardPerShare: 0,
                isInspire: true
            })
        );
    }

    function updateRewardPerBlock(uint256 _rewardPerSecond, uint256 _pid) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        require(_pid > 2, "can not update reward");
        updatePool(_pid);
        pool.rewardPerSecond = _rewardPerSecond;
    }

    function withdrawReward(address token, uint256 amount) external onlyOwner {
        IStrictERC20(token).transfer(msg.sender, amount);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending CAKEs on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 rewardPerShare = pool.rewardPerShare;
        uint256 lpSupply = 0;
        if (pool.isInspire) {
            Rebase memory lpSupplyRebase = ICauldronV4(pool.stakeToken).totalBorrow();
            if (block.timestamp > pool.lastRewardTimestamp && lpSupplyRebase.base != 0) {
                lpSupply = lpSupplyRebase.base;
            }
        } else if (_pid == 0) {
            uint256 rPerSencond = pool.rewardPerSecond;
            uint256 epoch = block.timestamp;
            uint256 userLockAmount = getLockAmount(_user);
            if (epoch > pool.lastRewardTimestamp && userLockAmount != 0) {
                uint256 lrt = pool.lastRewardTimestamp;
                for (uint i = arvLastRelease; i < epoch; ) {
                    i += 1 days;
                    uint256 timestamp = Math.min(epoch, i);
                    uint256 multiplier = getMultiplier(lrt, timestamp);
                    uint256 reward = multiplier.mul(rPerSencond);
                    if (timestamp < epoch) {
                        rPerSencond = (rPerSencond * 999) / 1000;
                    }
                    rewardPerShare = rewardPerShare.add(reward.mul(1e20).div(totalVinLock));
                    lrt = timestamp;
                }
            }
            return userLockAmount.mul(rewardPerShare).div(1e20).sub(user.rewardDebt);
        } else {
            lpSupply = totalStake[_pid];
        }
        if (lpSupply == 0) {
            return 0;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTimestamp, block.timestamp);
        uint256 reward = multiplier.mul(pool.rewardPerSecond);
        rewardPerShare = rewardPerShare.add(reward.mul(1e20).div(lpSupply));
        return user.amount.mul(rewardPerShare).div(1e20).sub(user.rewardDebt);
    }

    function getLockInfo(address user) external view returns (LockDetail[] memory locks) {
        uint256 unlockCount = userLock[user].length - userUnlockIndex[user];
        locks = new LockDetail[](unlockCount);
        for (uint256 i = 0; i < unlockCount; i++) {
            locks[i] = (userLock[user][i + userUnlockIndex[user]]);
        }
    }

    function getLockAmount(address user) public view returns (uint256 amount) {
        LockDetail[] memory details = userLock[user];
        uint256 unlockIndex = userUnlockIndex[user];
        for (uint256 i = unlockIndex; i < details.length; i++) {
            amount += details[i].lockAmount - details[i].unlockAmount;
        }
    }

    function getUnlockableAmount(address user) public view returns (uint256 amount) {
        LockDetail[] memory details = userLock[user];
        uint256 unlockIndex = userUnlockIndex[user];
        for (uint256 i = unlockIndex; i < details.length; i++) {
            if (details[i].unlockTimestamp <= block.timestamp) {
                amount += details[i].lockAmount - details[i].unlockAmount;
            } else {
                break;
            }
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
        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = 0;
        if (pool.isInspire) {
            Rebase memory lpSupplyRebase = ICauldronV4(pool.stakeToken).totalBorrow();
            lpSupply = lpSupplyRebase.base;
        } else if (_pid == 0) {
            uint256 epoch = block.timestamp;
            for (uint i = arvLastRelease; i < epoch; ) {
                i += 1 days;
                uint256 timestamp = Math.min(epoch, i);
                uint256 multiplier = getMultiplier(pool.lastRewardTimestamp, timestamp);
                uint256 reward = multiplier.mul(pool.rewardPerSecond);
                if (timestamp < epoch) {
                    arvLastRelease = i;
                    pool.rewardPerSecond = (pool.rewardPerSecond * 999) / 1000;
                }
                arvCirculatingSupply += reward;
                if (totalVinLock > 0) {
                    pool.rewardPerShare = pool.rewardPerShare.add(reward.mul(1e20).div(totalVinLock));
                }
                pool.lastRewardTimestamp = timestamp;
            }
        } else {
            uint256 lpSupply = totalStake[_pid];
        }
        if (lpSupply == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTimestamp, block.timestamp);
        uint256 reward = multiplier.mul(pool.rewardPerSecond);
        pool.rewardPerShare = pool.rewardPerShare.add(reward.mul(1e20).div(lpSupply));
        pool.lastRewardTimestamp = block.timestamp;
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        _deposit(address(0), _pid, _amount);
    }

    function deposit(address to) public {
        _deposit(to, 0, 0);
    }

    function depositLock(uint256 _amount) public {
        _deposit(address(0), 1, _amount);
        updatePool(0);
        address to = msg.sender;
        uint256 userLockAmount = getLockAmount(to);
        PoolInfo memory pool = poolInfo[0];
        UserInfo storage user = userInfo[0][to];
        if (userLockAmount > 0) {
            uint256 pending = userLockAmount.mul(pool.rewardPerShare).div(1e20).sub(user.rewardDebt);
            if (pending > 0) {
                arv.transfer(to, pending);
            }
        }
        userLockAmount += _amount;
        userLock[msg.sender].push(LockDetail({lockAmount: _amount, unlockAmount: 0, unlockTimestamp: block.timestamp + 16 weeks}));
        user.rewardDebt = userLockAmount.mul(pool.rewardPerShare).div(1e20);
        totalVinLock += _amount;
    }

    /// @notice Deposit tokens to MasterChef.
    /// @param to can be address(0) if the pool is inspire reward. otherwise please use the user address;
    /// @param _pid can be 0 if the pool is non inspire reward
    /// @param _amount can be 0 if the pool is non inspire reward
    function _deposit(address to, uint256 _pid, uint256 _amount) private {
        if (_pid == 0) {
            _pid = cauldronPoolInfo[msg.sender];
        }
        if (_pid == 0) {
            return;
        }
        updatePool(_pid);
        PoolInfo memory pool = poolInfo[_pid];
        if (!pool.isInspire) {
            to = msg.sender;
        } else {
            require(msg.sender == pool.stakeToken, "only cauldron can deposit inspire pool");
        }
        UserInfo storage user = userInfo[_pid][to];
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.rewardPerShare).div(1e20).sub(user.rewardDebt);
            if (pending > 0) {
                if (pool.isInspire) {
                    userPendingReward[to] += pending;
                } else {
                    IStrictERC20(pool.rewardToken).transfer(to, pending);
                }
            }
        }
        if (pool.isInspire) {
            uint256 newAmount = ICauldronV4(pool.stakeToken).userBorrowPart(to);
            emit Deposit(msg.sender, _pid, newAmount - user.amount);
            user.amount = newAmount;
        } else {
            if (_amount > 0) {
                IStrictERC20(pool.stakeToken).transferFrom(address(to), address(this), _amount);
                user.amount = user.amount.add(_amount);
                totalStake[_pid] += _amount;
                emit Deposit(msg.sender, _pid, _amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(1e20);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        _withdraw(address(0), _pid, _amount, false);
    }

    function withdrawLock(uint256 _amount) public {
        updatePool(0);
        address to = msg.sender;
        uint256 userLockAmount = getLockAmount(to);
        PoolInfo memory pool = poolInfo[0];
        UserInfo storage user = userInfo[0][to];
        if (userLockAmount > 0) {
            uint256 pending = userLockAmount.mul(pool.rewardPerShare).div(1e20).sub(user.rewardDebt);
            if (pending > 0) {
                arv.transfer(to, pending);
            }
        }
        userLockAmount -= _amount;
        user.rewardDebt = userLockAmount.mul(pool.rewardPerShare).div(1e20);
        totalVinLock -= _amount;
        _withdraw(address(0), 1, _amount, true);
    }

    function withdraw(address[] calldata to) public {
        for (uint256 i = 0; i < to.length; i++) {
            withdraw(to[i]);
        }
    }

    function withdraw(address to) public {
        _withdraw(to, 0, 0, false);
    }

    /// @notice Withdraw tokens from MasterChef.
    /// @param to can be address(0) if the pool is inspire reward. otherwise please use the user address;
    /// @param _pid can be 0 if the pool is non inspire reward
    /// @param _amount can be 0 if the pool is non inspire reward
    function _withdraw(address to, uint256 _pid, uint256 _amount, bool unlockVIN) private {
        if (_pid == 0) {
            _pid = cauldronPoolInfo[msg.sender];
        }
        if (_pid == 0) {
            return;
        }
        updatePool(_pid);
        PoolInfo memory pool = poolInfo[_pid];
        if (!pool.isInspire) {
            to = msg.sender;
        } else {
            require(msg.sender == pool.stakeToken, "only cauldron can deposit inspire pool");
        }
        UserInfo storage user = userInfo[_pid][to];
        require(user.amount >= _amount, "withdraw: not good");
        uint256 pending = user.amount.mul(pool.rewardPerShare).div(1e20).sub(user.rewardDebt);
        if (pending > 0) {
            if (pool.isInspire) {
                userPendingReward[to] += pending;
            } else {
                IStrictERC20(pool.rewardToken).transfer(to, pending);
            }
        }
        if (pool.isInspire) {
            uint256 oldAmount = ICauldronV4(pool.stakeToken).userBorrowPart(to);
            emit Withdraw(to, _pid, user.amount - oldAmount);
            user.amount = oldAmount;
        } else {
            if (_amount > 0) {
                if (pool.stakeToken == address(vin) && unlockVIN) {
                    uint256 epoch = block.timestamp;
                    require(getUnlockableAmount(to) >= _amount, "no enough unlockable");
                    uint256 unlockAmountLeft = _amount;
                    uint256 i = 0;
                    uint256 unlockIndex = userUnlockIndex[to];
                    LockDetail[] storage details = userLock[to];
                    for (i = unlockIndex; i < details.length && unlockAmountLeft > 0; i++) {
                        LockDetail storage detail = userLock[to][i];
                        if (detail.unlockTimestamp <= epoch) {
                            uint256 unlockableAmount = detail.lockAmount - detail.unlockAmount;
                            if (unlockableAmount <= unlockAmountLeft) {
                                unlockAmountLeft -= unlockableAmount;
                                detail.unlockAmount = detail.lockAmount;
                            } else {
                                detail.unlockAmount += unlockAmountLeft;
                                unlockAmountLeft = 0;
                                break;
                            }
                        }
                    }
                    userUnlockIndex[to] = i;
                } else {
                    require(user.amount.sub(getLockAmount(to)) >= _amount, "not enough amount");
                }
                user.amount = user.amount.sub(_amount);
                totalStake[_pid] -= _amount;
                IStrictERC20(pool.stakeToken).transfer(to, _amount);
                emit Withdraw(to, _pid, _amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(1e20);
    }

    function claimPending(uint256 _pid) public {
        updatePool(_pid);
        PoolInfo memory pool = poolInfo[_pid];
        address to = msg.sender;
        UserInfo storage user = userInfo[_pid][to];
        if (_pid == 0) {
            uint256 userLockAmount = getLockAmount(to);
            if (userLockAmount > 0) {
                uint256 pending = userLockAmount.mul(pool.rewardPerShare).div(1e20).sub(user.rewardDebt);
                user.rewardDebt = userLockAmount.mul(pool.rewardPerShare).div(1e20);
                if (pending > 0) {
                    arv.transfer(to, pending);
                }
            }
        } else {
            uint256 pending = user.amount.mul(pool.rewardPerShare).div(1e20).sub(user.rewardDebt);
            user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(1e20);
            if (pending > 0) {
                if (pool.isInspire) {
                    userPendingReward[to] += pending;
                } else {
                    IStrictERC20(pool.rewardToken).transfer(to, pending);
                }
            }
        }
    }

    function vestingPendingReward(bool claim) public {
        if (claim) {
            for (uint256 i = 3; i < poolInfo.length; i++) {
                PoolInfo memory pool = poolInfo[i];
                if (pool.isInspire) {
                    claimPending(i);
                }
            }
        }
        userVestingInfo[msg.sender].push(
            VestingInfo({vestingReward: userPendingReward[msg.sender], claimTime: block.timestamp + 21 days, isClaimed: false})
        );
        userPendingReward[msg.sender] = 0;
    }

    function getUserVestingInfo(address user) external view returns (VestingInfo[] memory) {
        return userVestingInfo[user];
    }

    function claimVestingReward() public {
        VestingInfo[] storage details = userVestingInfo[msg.sender];
        uint256 reward = 0;
        uint256 i;
        for (i = userVestingIndex[msg.sender]; i < details.length; i++) {
            if (!details[i].isClaimed) {
                if (details[i].claimTime <= block.timestamp) {
                    details[i].isClaimed = true;
                    reward += details[i].vestingReward;
                } else {
                    break;
                }
            }
        }
        userVestingIndex[msg.sender] = i;
        vin.transfer(msg.sender, reward);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        require(_pid != 0, "can not emergency withdraw arv release pool");
        PoolInfo storage pool = poolInfo[_pid];
        require(!pool.isInspire, "inspire pool can not withdraw");
        address operator = msg.sender;
        UserInfo storage user = userInfo[_pid][operator];
        if (_pid == 1) {
            uint256 userLockAmount = getLockAmount(operator);
            totalVinLock -= userLockAmount;
            delete userLock[operator];
            delete userUnlockIndex[operator];
        }
        totalStake[_pid] -= user.amount;
        emit EmergencyWithdraw(operator, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        IStrictERC20(pool.stakeToken).transfer(operator, user.amount);
    }

    function estimateARVCirculatingSupply() public view returns (uint256 circulatingSupply) {
        PoolInfo memory pool = poolInfo[0];
        uint256 rPerSencond = pool.rewardPerSecond;
        uint256 epoch = block.timestamp;
        circulatingSupply = arvCirculatingSupply;
        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lrt = pool.lastRewardTimestamp;
            for (uint i = arvLastRelease; i < epoch; ) {
                i += 1 days;
                uint256 timestamp = Math.min(epoch, i);
                uint256 multiplier = getMultiplier(lrt, timestamp);
                uint256 reward = multiplier.mul(rPerSencond);
                if (i < epoch) {
                    rPerSencond = (rPerSencond * 999) / 1000;
                }
                circulatingSupply += reward;
                lrt = timestamp;
            }
        }
    }

    function getShareThatShouldDistribute() public view returns (uint256 share) {
        share = (totalStake[1] > 0 ? 50 : 0) + (totalStake[2] > 0 ? 10 : 0);
    }
}

