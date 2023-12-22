

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface token is IERC20 {
    function mint(address recipient, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external ;
}

contract LPstaking is Ownable,ReentrancyGuard {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    uint256 maxAllocation = 1000000e18;
    // Info of each user.
    struct UserInfo {

        uint256 vote;  
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt;
        uint256 xPRISMrewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of PRISMs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accPRISMPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accPRISMPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        bool voteable;
        uint256 allocPoint;       // How many allocation points assigned to this pool. PRISMs to distribute per block.
        uint256 lastRewardTime;  // Last block time that PRISMs distribution occurs.
        uint256 accPRISMPerShare; // Accumulated PRISMs per share, times 1e12. See below.
        uint256 accxPRISMPerShare; // Accumulated PRISMs per share, times 1e12. See below.
    }

    token public PRISM = token(0x0B5C6ac0E1082F2d81e829B8C2957886e6bb3994);
    token public xPRISM = token(0xFa3f42Aad340544Aa45159b0af8C0840fbD4E3b7);

    // Dev address.
    address public devaddr;
    address public stakepool;
    // PRISM tokens created per block.
    uint256 public PRISMPerSecond;
    uint256 public xPRISMPerSecond;

    uint256 public totalPRISMdistributed = 0;
    uint256 public xPRISMdistributed = 0;

    // set a max PRISM per second, which can never be higher than 1 per second
    uint256 public constant maxPRISMPerSecond = 1e18;
    uint256 public constant maxxPRISMPerSecond = 1e18;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block time when PRISM mining starts.
    uint256 public startTime;
    bool public startTimeChangeable = true;

    // bool public withdrawable = false;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        uint256 _PRISMPerSecond,
        uint256 _xPRISMPerSecond,
        uint256 _startTime
    ) {

        PRISMPerSecond = _PRISMPerSecond;
        xPRISMPerSecond = _xPRISMPerSecond;
        startTime = _startTime;
    }


    // function openWithdraw() external onlyOwner{
    //     withdrawable = true;
    // }

    function supplyRewards(uint256 _amount) external onlyOwner {
        totalPRISMdistributed = totalPRISMdistributed.add(_amount);
        PRISM.transferFrom(msg.sender, address(this), _amount);
    }
    
    // function closeWithdraw() external onlyOwner{
    //     withdrawable = false;
    // }

            // Update the given pool's PRISM allocation point. Can only be called by the owner.
    function increaseAllocation(uint256 _pid, uint256 _allocPoint) internal {

        massUpdatePools();

        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo[_pid].allocPoint = poolInfo[_pid].allocPoint.add(_allocPoint);
    }
    
    function decreaseAllocation(uint256 _pid, uint256 _allocPoint) internal {

        massUpdatePools();

        totalAllocPoint = totalAllocPoint.sub(_allocPoint);
        poolInfo[_pid].allocPoint = poolInfo[_pid].allocPoint.sub(_allocPoint);
    }

    function vote(address _user, uint256 _amount, uint256 _pid) external {
        require(msg.sender == stakepool, "not stakepool");
        require(poolInfo[_pid].voteable, "vote not permitted");
        
        UserInfo storage user = userInfo[_pid][_user];
    
        if (_amount > user.vote){
            uint256 increaseAmount = _amount.sub(user.vote);
            user.vote = _amount;
            increaseAllocation(_pid, increaseAmount);
        } 
        else {
            uint256 decreaseAmount = user.vote.sub(_amount);
            user.vote = _amount;
            decreaseAllocation(_pid, decreaseAmount);
        }
    }

    function redeemVote(address _user, uint256 _pid) external {
        require(msg.sender == stakepool, "not stakepool");
        UserInfo storage user = userInfo[_pid][_user];
        decreaseAllocation(_pid, user.vote);
        user.vote = 0;
        
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Changes PRISM token reward per second, with a cap of maxPRISM per second
    // Good practice to update pools without messing up the contract
    function setPRISMPerSecond(uint256 _PRISMPerSecond) external onlyOwner {
        require(_PRISMPerSecond <= maxPRISMPerSecond, "setPRISMPerSecond: too many PRISMs!");

        // This MUST be done or pool rewards will be calculated with new PRISM per second
        // This could unfairly punish small pools that dont have frequent deposits/withdraws/harvests
        massUpdatePools(); 

        PRISMPerSecond = _PRISMPerSecond;
    }

    function setxPRISMPerSecond(uint256 _xPRISMPerSecond) external onlyOwner {
        require(_xPRISMPerSecond <= maxxPRISMPerSecond, "setxPRISMPerSecond: too many xPRISMs!");

        // This MUST be done or pool rewards will be calculated with new xPRISM per second
        // This could unfairly punish small pools that dont have frequent deposits/withdraws/harvests
        massUpdatePools(); 

        xPRISMPerSecond = _xPRISMPerSecond;
    }


    function checkForDuplicate(IERC20 _lpToken) internal view {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].lpToken != _lpToken, "add: pool already exists!!!!");
        }

    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken) external onlyOwner {

        checkForDuplicate(_lpToken); // ensure you cant add duplicate pools

        massUpdatePools();

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            voteable: true,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accPRISMPerShare: 0,
            accxPRISMPerShare: 0
        }));
    }

    // Update the given pool's PRISM allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) external onlyOwner {

        massUpdatePools();

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        require(totalAllocPoint <= maxAllocation);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function setVotePermission(uint256 _pid, bool _vote) external onlyOwner {

        massUpdatePools();

        poolInfo[_pid].voteable = _vote;
    }




    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        _from = _from > startTime ? _from : startTime;
        if (_to < startTime) {
            return 0;
        }
        return _to - _from;
    }

    // View function to see pending PRISMs on frontend.
    function pendingPRISM(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPRISMPerShare = pool.accPRISMPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 PRISMReward = multiplier.mul(PRISMPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accPRISMPerShare = accPRISMPerShare.add(PRISMReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accPRISMPerShare).div(1e12).sub(user.rewardDebt);
    }

    function pendingxPRISM(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accxPRISMPerShare = pool.accxPRISMPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 xPRISMReward = multiplier.mul(xPRISMPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accxPRISMPerShare = accxPRISMPerShare.add(xPRISMReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accxPRISMPerShare).div(1e12).sub(user.xPRISMrewardDebt);
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
        uint256 PRISMReward = multiplier.mul(PRISMPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 xPRISMReward = multiplier.mul(xPRISMPerSecond).mul(pool.allocPoint).div(totalAllocPoint);

        pool.accPRISMPerShare = pool.accPRISMPerShare.add(PRISMReward.mul(1e12).div(lpSupply));
        pool.accxPRISMPerShare = pool.accxPRISMPerShare.add(xPRISMReward.mul(1e12).div(lpSupply));
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens to MasterChef for PRISM allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accPRISMPerShare).div(1e12).sub(user.rewardDebt);
        uint256 EsPending = user.amount.mul(pool.accxPRISMPerShare).div(1e12).sub(user.xPRISMrewardDebt);

        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accPRISMPerShare).div(1e12);
        user.xPRISMrewardDebt = user.amount.mul(pool.accxPRISMPerShare).div(1e12);

        if(pending > 0 || EsPending >0) {
            PRISM.mint(msg.sender, pending);
            safexPRISMTransfer(msg.sender, EsPending);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {  
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");
        // require(withdrawable, "withdraw not opened");

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accPRISMPerShare).div(1e12).sub(user.rewardDebt);
        uint256 EsPending = user.amount.mul(pool.accxPRISMPerShare).div(1e12).sub(user.xPRISMrewardDebt);

        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accPRISMPerShare).div(1e12);
        user.xPRISMrewardDebt = user.amount.mul(pool.accxPRISMPerShare).div(1e12);

        if(pending > 0 || EsPending > 0) {
            PRISM.mint(msg.sender, pending);
            safexPRISMTransfer(msg.sender, EsPending);
        }
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function updateStakePool(address _pool) external onlyOwner {
        stakepool = _pool;
    } 

    function updateMinters(token _PRISM, token _xPRISM) external onlyOwner {
        xPRISM = _xPRISM;
        PRISM = _PRISM;
    }
    function safexPRISMTransfer(address _to, uint256 _amount) internal {
        uint256 WETHBal = xPRISM.balanceOf(address(this));
        if (_amount > WETHBal) {
            xPRISM.transfer(_to, WETHBal);
        } else {
            xPRISM.transfer(_to, _amount);
        }
    }

    function recoverxPRISM() external onlyOwner {
        uint256 balance = xPRISM.balanceOf(address(this));
        require(balance > 0, "No tokens to recover");
        xPRISM.transfer(msg.sender, balance);
    }

    function updateStartTime(uint256 _time) external onlyOwner {
        require(startTimeChangeable == true, "Cant change start time");
        startTime = _time;
    }
    
    function closeChangeStartTime() external onlyOwner {
        startTimeChangeable = false;
    }
}
