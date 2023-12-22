// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./OnyxToken.sol";
import "./IRewarder.sol";

// MasterChef is the master of ONYX. He can make ONYX and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once ONYX is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChefOnyx is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of ONYXs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accOnyxPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws tokens to a pool. Here's what happens:
        //   1. The pool's `accOnyxPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 stakeToken;        // Address of stake token contract.
        IRewarder rewarder;       // Address of rewarder contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. ONYXs to distribute per block.
        uint256 totalStaked;      // Amount of tokens staked in given pool
        uint256 lastRewardTime;   // Last timestamp ONYXs distribution occurs.
        uint256 accOnyxPerShare;  // Accumulated ONYXs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // The ONYX TOKEN!
    OnyxToken public onyx;
    // Dev address.
    address public devaddr;
    // Dev fee percentage.
    uint256 public devFee = 100;
    // ONYX tokens created per second.
    uint256 public onyxPerSecond;
    // Deposit Fee address
    address public feeAddress;

    // Max emission rate
    uint256 public constant MAX_EMISSION_RATE = 50;
    // Max dev fee
    uint256 public constant MAX_DEV_FEE = 100;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when ONYX mining starts.
    uint256 public startTime;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 onyxPerSecond);
    event UpdateDevFee(address indexed user, uint256 newFee);

    event LogPoolAddition(uint256 indexed pid, uint256 allocPoint, IERC20 indexed stakeToken, uint16 depositFee, IRewarder indexed rewarder);
    event LogSetPool(uint256 indexed pid, uint256 allocPoint,  uint16 depositFee, IRewarder indexed rewarder);
    event LogUpdatePool(uint256 indexed pid, uint256 lastRewardBlock, uint256 stakeSupply, uint256 accOnyxPerShare);

    constructor(
        OnyxToken _onyx,
        address _devaddr,
        address _feeAddress,
        uint256 _onyxPerSecond,
        uint256 _startTime
    ) {
        onyx = _onyx;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        onyxPerSecond = _onyxPerSecond;
        startTime = _startTime;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _stakeToken) {
        require(poolExistence[_stakeToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new token to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _stakeToken, uint16 _depositFeeBP, bool _withUpdate, IRewarder _rewarder) public onlyOwner nonDuplicated(_stakeToken) {
        require(_depositFeeBP <= 1000, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_stakeToken] = true;

        poolInfo.push(PoolInfo({
            stakeToken : _stakeToken,
            rewarder: _rewarder,
            allocPoint : _allocPoint,
            lastRewardTime : lastRewardTime,
            accOnyxPerShare : 0,
            totalStaked : 0,
            depositFeeBP : _depositFeeBP
        }));

        emit LogPoolAddition(poolInfo.length.sub(1), _allocPoint, _stakeToken, _depositFeeBP, _rewarder);
    }

    // Update the given pool's ONYX allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate, IRewarder _rewarder) public onlyOwner {
        require(_depositFeeBP <= 1000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        } else {
            updatePool(_pid);
        }

        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].rewarder = _rewarder;

        emit LogSetPool(_pid, _allocPoint, _depositFeeBP, _rewarder);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending ONYXs on frontend.
    function pendingTokens(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accOnyxPerShare = pool.accOnyxPerShare;
        uint256 stakeSupply = pool.totalStaked;
        if (block.timestamp > pool.lastRewardTime && stakeSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 onyxReward = multiplier.mul(onyxPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accOnyxPerShare = accOnyxPerShare.add(onyxReward.mul(1e12).div(stakeSupply));
        }
        return user.amount.mul(accOnyxPerShare).div(1e12).sub(user.rewardDebt);
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
        uint256 stakeSupply = pool.totalStaked;
        if (stakeSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 totalOnyx = multiplier.mul(onyxPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        if (totalOnyx == 0) return;

        if(onyx.totalSupply() + totalOnyx > onyx.cap()) {
            totalOnyx = onyx.cap() - onyx.totalSupply();
            if(totalOnyx == 0 && onyxPerSecond != 0)
                return _updateEmissionRate(0);
        }

        uint256 forDevs = totalOnyx.mul(devFee).div(1000);
        uint256 onyxReward = totalOnyx.sub(forDevs);
        onyx.mint(devaddr, forDevs);
        onyx.mint(address(this), onyxReward);
        pool.accOnyxPerShare = pool.accOnyxPerShare.add(onyxReward.mul(1e12).div(stakeSupply));
        pool.lastRewardTime = block.timestamp;
        emit LogUpdatePool(_pid, pool.lastRewardTime, stakeSupply, pool.accOnyxPerShare);
    }

    // Deposit tokens to MasterChef for ONYX allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 finalDepositAmount;
        uint256 pending;
        updatePool(_pid);
        if (user.amount > 0) {
            pending = user.amount.mul(pool.accOnyxPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeOnyxTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            // Prefetch balance to account for transfer fees
            uint256 preStakeBalance = pool.stakeToken.balanceOf(address(this));
            pool.stakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            finalDepositAmount = pool.stakeToken.balanceOf(address(this)) - preStakeBalance;

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = finalDepositAmount.mul(pool.depositFeeBP).div(10000);
                pool.stakeToken.safeTransfer(feeAddress, depositFee);
                finalDepositAmount = finalDepositAmount.sub(depositFee);
            }
            user.amount = user.amount.add(finalDepositAmount);
            pool.totalStaked = pool.totalStaked.add(finalDepositAmount);
        }
        // Interactions
        if (address(pool.rewarder) != address(0)) {
            tryCatchOnReward(_pid, pending, user.amount);
        }
        user.rewardDebt = user.amount.mul(pool.accOnyxPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, finalDepositAmount);
    }

    // Withdraw tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accOnyxPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeOnyxTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalStaked = pool.totalStaked.sub(_amount);
            pool.stakeToken.safeTransfer(address(msg.sender), _amount);
        }   
        // Interactions
        if (address(pool.rewarder) != address(0)) {
            tryCatchOnReward(_pid, pending, user.amount);
        }
        user.rewardDebt = user.amount.mul(pool.accOnyxPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalStaked = pool.totalStaked.sub(amount);
        pool.stakeToken.safeTransfer(address(msg.sender), amount);
        // Interactions
        if (address(pool.rewarder) != address(0)) {
            tryCatchOnReward(_pid, 0, user.amount);
        }
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe onyx transfer function, just in case if rounding error causes pool to not have enough ONYXs.
    function safeOnyxTransfer(address _to, uint256 _amount) internal {
        uint256 onyxBal = onyx.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > onyxBal) {
            transferSuccess = onyx.transfer(_to, onyxBal);
        } else {
            transferSuccess = onyx.transfer(_to, _amount);
        }
        require(transferSuccess, "safeOnyxTransfer: transfer failed");
    }

    function tryCatchOnReward(uint256 _pid, uint256 _pending, uint256 _amount) internal returns (bool) {
        try poolInfo[_pid].rewarder.onReward(_pid, msg.sender, msg.sender, _pending, _amount) {
            return true;
        } catch {
            return false;
        }
    }

    /// @param _startTime The block to start mining
    /// @notice can only be changed if farming has not started already
    function setStartTime(uint256 _startTime) external onlyOwner {
        require(startTime > block.timestamp, "Farming started");
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardTime = _startTime;
        }
        startTime = _startTime;
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function _updateEmissionRate(uint256 _onyxPerSecond) internal {
        require(_onyxPerSecond <= MAX_EMISSION_RATE, "Updated emissions are more than maximum rate");
        onyxPerSecond = _onyxPerSecond;
        emit UpdateEmissionRate(msg.sender, _onyxPerSecond);
    }

    function updateEmissionRate(uint256 _onyxPerSecond) public onlyOwner {
        _updateEmissionRate(_onyxPerSecond);
        massUpdatePools();
    }    
    
    function updateDevFee(uint256 _newDevFee) public onlyOwner {
        require(_newDevFee <= MAX_DEV_FEE, "Updated fee is more than maximum rate");
        devFee = _newDevFee;
        emit UpdateDevFee(msg.sender, _newDevFee);
    }
}
