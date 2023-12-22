// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import "./SafeERC20.sol";

import "./PanaAccessControlled.sol";


// The StakingPools contract distributes Pana tokens to the users who stake certain tokens here.
// It is a fork of Giddy's GiddyChef contract which in turn is a fork of MasterChef by SushiSwap.
contract StakingPools is PanaAccessControlled {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Pana
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accPanaPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws tokens to a pool. Here's what happens:
        //   1. The pool's `accPanaPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token;             // Address of a deposit token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool.
        uint256 lastRewardTime;   // Last block time that Pana distribution occurs.
        uint256 accPanaPerShare;  // Accumulated Pana per share, times 1e12. See below.
    }

    IERC20 public immutable PANA;

    // Pana tokens distributed per second.
    uint256 public panaPerSecond;
 
    uint256 public constant MaxAllocPoint = 4000;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block time when Pana mining starts.
    uint256 public startTime;
    // The block time when Pana mining stops.
    uint256 public endTime;

    // Escrow that holds rewards
    address public escrow;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        address _pana,
        address _escrow,
        uint256 _panaPerSecond,
        uint256 _startTime,
        uint256 _endTime,
        address _authority
    ) PanaAccessControlled(IPanaAuthority(_authority)) {
        require(_pana != address(0), "Zero address: PANA");
        PANA = IERC20(_pana);
        escrow = _escrow;
        panaPerSecond = _panaPerSecond;
        startTime = _startTime;
        endTime = _endTime;

        totalAllocPoint = 0;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function checkForDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].token != _token, "Pool already exists!");
        }
    }

    // Sets new escrow address
    function setEscrow(address _escrow) external onlyGovernor {
        escrow = _escrow;
    }

    // Add a new pool.
    function add(uint256 _allocPoint, IERC20 _token) external onlyGovernor {
        require(_allocPoint <= MaxAllocPoint, "Too many alloc points!");

        checkForDuplicate(_token); // ensure you can't add duplicate pools
        massUpdatePools();

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(PoolInfo({
            token: _token,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accPanaPerShare: 0
        }));
    }

    // Update the given pool's allocation point.
    function set(uint256 _pid, uint256 _allocPoint) external onlyGovernor {
        require(_allocPoint <= MaxAllocPoint, "Too many alloc points!");

        massUpdatePools();

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to timestamp.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        _from = _from > startTime ? _from : startTime;
        if (_to < startTime || _from >= endTime) {
            return 0;
        } else if (_to <= endTime) {
            return _to - _from;
        } else {
            return endTime - _from;
        }
    }

    // View function to see pending Pana on frontend.
    function pendingPana(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accPanaPerShare = pool.accPanaPerShare;
        uint256 supply = pool.token.balanceOf(address(this));

        if (block.timestamp > pool.lastRewardTime && supply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 panaReward = multiplier * panaPerSecond * pool.allocPoint / totalAllocPoint;
            accPanaPerShare = accPanaPerShare + panaReward * 1e12 / supply;
        }

        return user.amount * accPanaPerShare / 1e12 - user.rewardDebt;
    }

    function poolBalances(address _user) external view returns (uint256[] memory) {
        uint256 length = poolInfo.length;
        uint256[] memory poolBalanceData = new uint256[](length);

        for (uint256 _pid = 0; _pid < length; ++_pid) {
            UserInfo storage user = userInfo[_pid][_user];
            poolBalanceData[_pid] = user.amount;
        }
        return poolBalanceData;
    }

    // View function to see pending Pana on frontend.
    function pendingPanaForUser(address _user) external view returns (uint256[] memory) {
        uint256 length = poolInfo.length;
        uint256[] memory pendingPanaValues = new uint256[](length);

        for (uint256 _pid = 0; _pid < length; ++_pid) {
            PoolInfo storage pool = poolInfo[_pid];
            UserInfo storage user = userInfo[_pid][_user];
            uint256 accPanaPerShare = pool.accPanaPerShare;
            uint256 supply = pool.token.balanceOf(address(this));

            if (block.timestamp > pool.lastRewardTime && supply != 0) {
                uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
                uint256 panaReward = multiplier * panaPerSecond * pool.allocPoint / totalAllocPoint;
                accPanaPerShare = accPanaPerShare + panaReward * 1e12 / supply;
            }

            pendingPanaValues[_pid] = user.amount * accPanaPerShare / 1e12 - user.rewardDebt;
        }
        return pendingPanaValues;
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

        uint256 supply = pool.token.balanceOf(address(this));
        if (supply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 panaReward = multiplier * panaPerSecond * pool.allocPoint / totalAllocPoint;

        pool.accPanaPerShare = pool.accPanaPerShare + panaReward * 1e12 / supply;
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit tokens to staking.
    function deposit(uint256 _pid, uint256 _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        uint256 pending = user.amount * pool.accPanaPerShare / 1e12 - user.rewardDebt;

        user.amount = user.amount + _amount;
        user.rewardDebt = user.amount * pool.accPanaPerShare / 1e12;

        if(pending > 0) {
            PANA.safeTransferFrom(escrow, msg.sender, pending);
        }
        pool.token.safeTransferFrom(address(msg.sender), address(this), _amount);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw tokens from staking.
    function withdraw(uint256 _pid, uint256 _amount) external {  
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "Insufficient funds");

        updatePool(_pid);

        uint256 pending = user.amount * pool.accPanaPerShare / 1e12 - user.rewardDebt;

        user.amount = user.amount - _amount;
        user.rewardDebt = user.amount * pool.accPanaPerShare / 1e12;

        if(pending > 0) {
            PANA.safeTransferFrom(escrow, msg.sender, pending);
        }
        pool.token.safeTransfer(address(msg.sender), _amount);
        
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function harvestAll() public {
        uint256 length = poolInfo.length;
        uint calc;
        uint pending;
        UserInfo storage user;
        PoolInfo storage pool;
        uint totalPending;

        for (uint256 pid = 0; pid < length; ++pid) {
            user = userInfo[pid][msg.sender];
            if (user.amount > 0) {
                pool = poolInfo[pid];
                updatePool(pid);

                calc = user.amount * pool.accPanaPerShare / 1e12;
                pending = calc - user.rewardDebt;
                user.rewardDebt = calc;

                if(pending > 0) {
                    totalPending += pending;
                }
            }
        }

        if (totalPending > 0) {
            PANA.safeTransferFrom(escrow, msg.sender, totalPending);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint oldUserAmount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        pool.token.safeTransfer(address(msg.sender), oldUserAmount);
        emit EmergencyWithdraw(msg.sender, _pid, oldUserAmount);
    }

    function setStartTime(uint256 _newStartTime) external onlyGovernor {
        require(startTime > block.timestamp, "Already started");
        require(_newStartTime > block.timestamp, "New time in the past");

        startTime = _newStartTime;
    }

    function setEndTime(uint256 _newEndTime) external onlyGovernor {
        require(endTime > block.timestamp, "Already ended");
        require(_newEndTime > block.timestamp, "New end time in the past");

        endTime = _newEndTime;
    }

    function setPanaPerSecond(uint256 _panaPerSecond) external onlyGovernor {
        panaPerSecond = _panaPerSecond;
    }
}
