// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

import "./SafeMath.sol";
import "./IBEP20.sol";
import "./SafeBEP20.sol";
import "./Ownable.sol";

import "./Sky.sol";

// import "@nomiclabs/buidler/console.sol";

// MasterWhale is the master of Sky. He can make Sky and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Sky is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterWhale1 is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Skys
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSkyPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSkyPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. Skys to distribute per block.
        uint256 lastRewardBlockTime;  // Last block number that Skys distribution occurs.
        uint256 accSkyPerShare; // Accumulated Skys per share, times 1e12. See below.
    }

    // The DEX TOKEN!
    NativeToken public sky;
    // sky tokens created per block - ownerFee.
    uint256 public skyPerSecond;
    // Bonus muliplier for early sky makers.
    uint256 public BONUS_MULTIPLIER = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // Allocation ratio for pool 0
    uint8 public allocRatio = 2;

    bool public singlePoolEnabled = false;

    // The block number when sky mining starts.
    uint256 public startTime = type(uint256).max;
    // Owner fee
    uint256 public constant ownerFee = 2000; // 20%

    mapping (address => bool) public lpTokenAdded;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        NativeToken _sky,
        uint256 _skyPerSecond
    ) {
        sky = _sky;
        skyPerSecond = _skyPerSecond;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _sky,
            allocPoint: singlePoolEnabled ? 1000 : 0,
            lastRewardBlockTime: startTime,
            accSkyPerShare: 0
        }));

        totalAllocPoint = singlePoolEnabled ? 1000 : 0;

    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner {
        require(lpTokenAdded[address(_lpToken)] == false, 'Pool for this token already exists!');
        lpTokenAdded[address(_lpToken)] = true;

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlockTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlockTime: lastRewardBlockTime,
            accSkyPerShare: 0
        }));
        updateStakingPool();
    }

    // Update the given pool's sky allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = singlePoolEnabled ? points.div(allocRatio) : 0;
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending skys on frontend.
    function pendingSky(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSkyPerShare = pool.accSkyPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardBlockTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlockTime, block.timestamp);
            uint256 skyReward = multiplier.mul(skyPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accSkyPerShare = accSkyPerShare.add(skyReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accSkyPerShare).div(1e12).sub(user.rewardDebt);
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
        if (block.timestamp <= pool.lastRewardBlockTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlockTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlockTime, block.timestamp);
        uint256 skyReward = multiplier.mul(skyPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        sky.mint(skyReward);
        pool.accSkyPerShare = pool.accSkyPerShare.add(skyReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlockTime = block.timestamp;

        // mint ownerFee
        sky.mintFor(owner(), skyReward.mul(ownerFee).div(10000));
    }

    // Deposit LP tokens to MasterWhale for sky allocation.
    function deposit(uint256 _pid, uint256 _amount) public {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accSkyPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeSkyTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            uint256 before = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 _after = pool.lpToken.balanceOf(address(this));
            _amount = _after.sub(before);

            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accSkyPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Stake sky tokens to MasterWhale
    function enterStaking(uint256 _amount) public {
        deposit(0, _amount);
    }

    // Withdraw LP tokens from MasterWhale.
    function withdraw(uint256 _pid, uint256 _amount) public {
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accSkyPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeSkyTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accSkyPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw Sky tokens from STAKING.
    function leaveStaking(uint256 _amount) public {
        withdraw(0, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe DEX transfer function, just in case if rounding error causes pool to not have enough DEX.
    function safeSkyTransfer(address _to, uint256 _amount) internal {
        sky.safeSkyTransfer(_to, _amount);
    }

    // Update pool 0 allocation ratio. Can only be called by the owner.
    function setAllocRatio(uint8 _allocRatio) public onlyOwner {
        require(
            _allocRatio >= 1 && _allocRatio <= 10, 
            "Allocation ratio must be in range 1-10"
        );

        allocRatio = _allocRatio;
    }

    // reduce DEX emissions
    function changeEmissions(uint256 _mintAmt) external onlyOwner {
        require(_mintAmt.mul(100).div(skyPerSecond) >= 95, "Max 5% decrease/increase per transaction.");
        skyPerSecond = _mintAmt;
    }

    function setStartTime(uint256 _startTime) external onlyOwner {
        require(block.timestamp < startTime && block.timestamp < _startTime);
        startTime = _startTime;

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            poolInfo[pid].lastRewardBlockTime = startTime;
        }
    }

    function skySinglePoolEnabled() external onlyOwner {
        singlePoolEnabled = !singlePoolEnabled;
        massUpdatePools();
        updateStakingPool();
    }
}
