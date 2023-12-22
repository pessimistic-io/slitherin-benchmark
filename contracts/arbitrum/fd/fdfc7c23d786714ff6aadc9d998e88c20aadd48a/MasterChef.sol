// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./VaultToken.sol";

contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Tokenes
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTokenPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accTokenPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct LockInfo {
        uint256 amount;
        uint256 timeUnlock;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Tokenes to distribute per block.
        uint256 lastRewardBlock; // Last block number that Tokenes distribution occurs.
        uint256 accTokenPerShare; // Accumulated Tokenes per share, times 1e18. See below.
    }

    // Reward TOKEN!
    IERC20 public token;
    VaultToken public vault;
    //tokens created per block.
    uint256 public tokenPerBlock = 1250000000000000000000;

    bool public paused = false;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Info of each user that lock LP tokens.
    mapping(uint256 => mapping(address => LockInfo)) public lockLpInfo;
    // Info of each user that lock reward tokens.
    mapping(uint256 => mapping(address => LockInfo)) public lockRewardInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when Test mining starts.
    uint256 public startBlock;
    // Time lock LP when withdraw
    uint256 public lockLpTime = 60 days;
    uint256 public lockRewardTime = 0 days;
    uint256 public lockRewardPercent = 0;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Vesting(address indexed user, uint256 indexed index, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdateEmissionRate(address indexed user, uint256 tokenPerBlock);
    event UnlockLp(address indexed user, uint256 amount);
    event UnlockReward(address indexed user, uint256 amount);

    constructor(
        address _token,
        address _vault,
        uint256 _startBlock
    ) {
        token = IERC20(_token);
        vault = VaultToken(_vault);
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    modifier notPause() {
        require(paused == false, "farm pool pause");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken
    ) external onlyOwner nonDuplicated(_lpToken) {
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(
            PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accTokenPerShare : 0
        })
        );
    }

    // Update the given pool's Test allocation point and deposit fee. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint
    ) external onlyOwner {
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending tokenes on frontend.
    function pendingToken(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accTokenPerShare = accTokenPerShare.add(tokenReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accTokenPerShare).div(1e18).sub(user.rewardDebt);
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
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        vault.farm(address(this), tokenReward);

        pool.accTokenPerShare = pool.accTokenPerShare.add(tokenReward.mul(1e18).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to Masterchef.
    function deposit(uint256 _pid, uint256 _amount) public notPause nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        LockInfo storage lockRwInfo = lockRewardInfo[_pid][msg.sender];

        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e18).sub(user.rewardDebt);
            if (pending > 0) {
                lockRwInfo.amount += pending * lockRewardPercent / 100;
                safeTokenTransfer(msg.sender, pending * (100-lockRewardPercent) / 100);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            if(lockRwInfo.timeUnlock == 0) {
                //first time deposit
                lockRwInfo.amount = 0;
                lockRwInfo.timeUnlock = block.timestamp + lockRewardTime;
            }
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public notPause nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        LockInfo storage lockRwInfo = lockRewardInfo[_pid][msg.sender];
        require(user.amount >= _amount && user.amount > 0, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e18).sub(user.rewardDebt);
        if (pending > 0) {
            lockRwInfo.amount += pending * lockRewardPercent / 100;
            safeTokenTransfer(msg.sender, pending * (100-lockRewardPercent) / 100);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            LockInfo storage lockInfo = lockLpInfo[_pid][msg.sender];
            lockInfo.amount = lockInfo.amount.add(_amount);
            lockInfo.timeUnlock = block.timestamp + lockLpTime;
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function unlockLp(uint256 _pid) public notPause nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        LockInfo storage lockInfo = lockLpInfo[_pid][msg.sender];
        require(lockInfo.amount > 0 , "unlockLp: not good");
        require(block.timestamp >= lockInfo.timeUnlock , "unlockLp: not time");
        uint256 amount = lockInfo.amount;
        updatePool(_pid);
        lockInfo.amount = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit UnlockLp(address(msg.sender), amount);
    }

    function unlockReward(uint256 _pid) public notPause nonReentrant {
        LockInfo storage lockRwInfo = lockRewardInfo[_pid][msg.sender];
        require(block.timestamp >= lockRwInfo.timeUnlock , "unlockReward: not time");
        require(lockRwInfo.amount > 0 , "unlockReward: not good");
        uint amount = lockRwInfo.amount;
        lockRwInfo.amount = 0;
        if(userInfo[_pid][msg.sender].amount == 0) {
            //if user withdraw all then reset time waiting to zero
            lockRwInfo.timeUnlock = 0;
        }
        safeTokenTransfer(msg.sender, amount);
        emit UnlockReward(msg.sender, amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        LockInfo storage lockInfo = lockLpInfo[_pid][msg.sender];
        lockInfo.amount = lockInfo.amount.add(amount);
        lockInfo.timeUnlock = block.timestamp + lockLpTime;
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe IToken transfer function, just in case if rounding error causes pool to not have enough FOXs.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = token.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > tokenBal) {
            transferSuccess = token.transfer(_to, tokenBal);
        } else {
            transferSuccess = token.transfer(_to, _amount);
        }
        require(transferSuccess, "safeTokenTransfer: Transfer failed");
    }


    function updateEmissionRate(uint256 _tokenPerBlock) external onlyOwner {
        massUpdatePools();
        tokenPerBlock = _tokenPerBlock;
        emit UpdateEmissionRate(msg.sender, tokenPerBlock);
    }


    function setPause(bool _paused) external onlyOwner {
        paused = _paused;
    }

    // Only update before start of farm
    function updateStartBlock(uint256 _startBlock) public onlyOwner {
        startBlock = _startBlock;
    }

    // Only update before start of farm
    function updateLockLpTime(uint256 _lockLpTime) external onlyOwner {
        lockLpTime = _lockLpTime;
    }

    // Only update before start of farm
    function updateLockRewardTime(uint256 _lockRewardTime) external onlyOwner {
        lockRewardTime = _lockRewardTime;
    }

    // Only update before start of farm
    function updateLockRewardPercent(uint256 _lockRewardPercent) external onlyOwner {
        lockRewardPercent = _lockRewardPercent;
    }

}
