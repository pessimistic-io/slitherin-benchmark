// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface stakingpool {
    function vote(address account, uint256 _amount, uint256 _poolid) external;

    function redeemVote(address account, uint256 _poolid) external;
}

interface IoldXCONEStaking {
    struct UserInfo {
    uint256 votePower;
    uint256 votedID;
    uint256 VestAmount;
    uint256 RPamount;
    uint256 amount; 
    uint256 rewardDebt; 
    uint256 RPrewardDebt; 
    }
    function userInfo(uint256 _pid, address account) external view returns (UserInfo memory);
    function pendingWETH(uint256 _pid, address _user) external view returns (uint256);
    function pendingRP(uint256 _pid, address _user) external view returns (uint256);
}

contract xCONEstaking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 votePower;
        uint256 votedID;
        uint256 RPamount;
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 RPrewardDebt; // Reward debt. See explanation below.
            //
            // We do some fancy math here. Basically, any point in time, the amount of WETHs
            // entitled to a user but is pending to be distributed is:
            //
            //   pending reward = (user.amount * pool.accWETHPerShare) - user.rewardDebt
            //
            // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
            //   1. The pool's `accWETHPerShare` (and `lastRewardBlock`) gets updated.
            //   2. User receives the pending reward sent to his/her address.
            //   3. User's `amount` gets updated.
            //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 totalRP;
        uint256 allocPoint; // How many allocation points assigned to this pool. WETHs to distribute per block.
        uint256 lastRewardTime; // Last block time that WETHs distribution occurs.
        uint256 accWETHPerShare; // Accumulated WETHs per share, times 1e12. See below.
        uint256 accRPPerShare; //RPpershare
    }

    IERC20 public WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    IoldXCONEStaking public constant oldXCONEStaking = IoldXCONEStaking(0x7246bC98791047378De9BD9cfdf050597a7eFAE8);    

    // Dev address.
    stakingpool public LPstake;
    // WETH tokens created per block.
    uint256 public WETHPerSecond;
    uint256 public RPPerSecond;

    uint256 public totalWETHdistributed = 0;

    // set a max WETH per second, which can never be higher than 1 per second
    uint256 public constant maxWETHPerSecond = 1e18;

    uint256 public constant MaxAllocPoint = 4000;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    mapping(address => bool) public voted;
    // The block time when WETH mining starts.
    uint64 public startTime;
    bool public withdrawable = false;

    mapping (address => uint256) public pendingClaims;

    address public helper;

    uint256 public fee;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event PendingClaimed(address indexed user, uint256 amount);
    event LPstakeUpdated(address indexed LPstake);
    event RewardUpdated(address indexed reward);
    event Migrated(address indexed user, uint256 amount);

    error WETH_NotSufficient();

    constructor(uint256 _WETHPerSecond, uint256 _RPPerSecond, uint64 _startTime, IERC20 xCONE) {
        WETHPerSecond = _WETHPerSecond;
        startTime = _startTime;
        RPPerSecond = _RPPerSecond;
        require(address(xCONE) != address(0), "xCONE can't be zero address");
        add(xCONE);
        fee = 50;
    }

    function setMigrationHelper(address _helper) external onlyOwner {
        helper = _helper;
    }

    function openWithdraw() external onlyOwner {
        withdrawable = true;
    }

    function setFee(uint256 _fee) external onlyOwner() {
        require(_fee <= 1000, "fee too high");
        fee = _fee;
    }

    function setStartTime(uint64 _startTime) external onlyOwner {
        require(block.timestamp < startTime, "already started");
        startTime = _startTime;
    }

    function supplyRewards(uint256 _amount) external onlyOwner {
        totalWETHdistributed = totalWETHdistributed.add(_amount);
        WETH.transferFrom(msg.sender, address(this), _amount);
    }

    function closeWithdraw() external onlyOwner {
        withdrawable = false;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Changes WETH token reward per second, with a cap of maxWETH per second
    // Good practice to update pools without messing up the contract
    function setWETHPerSecond(uint256 _WETHPerSecond) external onlyOwner {
        require(_WETHPerSecond <= maxWETHPerSecond, "setWETHPerSecond: too many WETHs!");

        // This MUST be done or pool rewards will be calculated with new WETH per second
        // This could unfairly punish small pools that dont have frequent deposits/withdraws/harvests
        massUpdatePools();

        WETHPerSecond = _WETHPerSecond;
    }

    function seRPPerSecond(uint256 _RPPerSecond) external onlyOwner {
        // This MUST be done or pool rewards will be calculated with new WETH per second
        // This could unfairly punish small pools that dont have frequent deposits/withdraws/harvests
        massUpdatePools();

        RPPerSecond = _RPPerSecond;
    }

    function getTotalVotePower(address _user, uint256 _pid) public view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        uint256 amount1 = user.amount + user.RPamount;
        return amount1;
    }

    function votePool(uint256 _pid) external {
        address _user = msg.sender;
        require(voted[_user] == false);
        uint256 userTotalVotePower = getTotalVotePower(_user, 0);
        require(userTotalVotePower > 0, " no voting power");
        UserInfo storage user = userInfo[0][_user];
        LPstake.vote(_user, userTotalVotePower, _pid);
        user.votedID = _pid;
        voted[_user] = true;
    }

    function updateVotePool(address _user) internal {
        if (voted[_user]) {
            UserInfo storage user = userInfo[0][_user];
            LPstake.vote(_user, getTotalVotePower(_user, 0), user.votedID);
        }
        if (getTotalVotePower(_user, 0) == 0) {
            voted[_user] = false;
        }
    }

    function unVotePool() external {
        address _user = msg.sender;
        require(voted[_user], "not voted");
        UserInfo storage user = userInfo[0][_user];
        LPstake.redeemVote(_user, user.votedID);
        voted[_user] = false;
    }

    function updateTotalVotePower(address _user, uint256 _pid) internal returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        user.votePower = getTotalVotePower(_user, _pid);
        return user.votePower;
    }

    function checkForDuplicate(IERC20 _lpToken) internal view {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].lpToken != _lpToken, "add: pool already exists!!!!");
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(IERC20 _lpToken) internal {
        checkForDuplicate(_lpToken); // ensure you cant add duplicate pools

        massUpdatePools();

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(1000);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                totalRP: 0,
                allocPoint: 1000,
                lastRewardTime: lastRewardTime,
                accWETHPerShare: 0,
                accRPPerShare: 0
            })
        );
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        _from = _from > startTime ? _from : startTime;
        if (_to < startTime) {
            return 0;
        }
        return _to - _from;
    }

    // View function to see pending WETHs on frontend.
    function pendingWETH(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accWETHPerShare = pool.accWETHPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 total = lpSupply.add(pool.totalRP);
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 WETHReward = multiplier.mul(WETHPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accWETHPerShare = accWETHPerShare.add(WETHReward.mul(1e12).div(total));
        }
        uint256 userPoint = user.amount.add(user.RPamount);
        return userPoint.mul(accWETHPerShare).div(1e12).sub(user.rewardDebt);
    }

    function pendingRP(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRPPerShare = pool.accRPPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 total = lpSupply.add(pool.totalRP);
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 RPReward = multiplier.mul(RPPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accRPPerShare = accRPPerShare.add(RPReward.mul(1e12).div(total));
        }
        uint256 userPoint = user.amount.add(user.RPamount);
        return userPoint.mul(accRPPerShare).div(1e12).sub(user.RPrewardDebt);
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
        uint256 total = lpSupply.add(pool.totalRP);
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 WETHReward = multiplier.mul(WETHPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 RPReward = multiplier.mul(RPPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accWETHPerShare = pool.accWETHPerShare.add(WETHReward.mul(1e12).div(total));
        pool.accRPPerShare = pool.accRPPerShare.add(RPReward.mul(1e12).div(total));
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens to MasterChef for WETH allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        uint256 _feeAmounts = _amount.mul(fee).div(10000);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        uint256 userPoint = user.amount.add(user.RPamount);
        uint256 pending = userPoint.mul(pool.accWETHPerShare).div(1e12).sub(user.rewardDebt);
        uint256 RPpending = userPoint.mul(pool.accRPPerShare).div(1e12).sub(user.RPrewardDebt);

        user.amount = user.amount.add(_amount).sub(_feeAmounts);
        user.RPamount = user.RPamount.add(RPpending);

        userPoint = user.amount.add(user.RPamount);
        user.rewardDebt = userPoint.mul(pool.accWETHPerShare).div(1e12);
        user.RPrewardDebt = userPoint.mul(pool.accRPPerShare).div(1e12);

        pool.totalRP = pool.totalRP.add(RPpending);
        updateTotalVotePower(msg.sender, _pid);
        updateVotePool(msg.sender);
        if (pending > 0) {
            safeWETHTransfer(msg.sender, pending, false);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        pool.lpToken.safeTransfer(owner(), _feeAmounts);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");
        require(withdrawable, "withdraw not opened");

        updatePool(_pid);

        uint256 userPoint = user.amount.add(user.RPamount);
        uint256 pending = userPoint.mul(pool.accWETHPerShare).div(1e12).sub(user.rewardDebt);

        user.amount = user.amount.sub(_amount);

        if (_amount > 0) {
            pool.totalRP = pool.totalRP.sub(user.RPamount);
            user.RPamount = 0;
        }
        userPoint = user.amount.add(user.RPamount);
        user.rewardDebt = userPoint.mul(pool.accWETHPerShare).div(1e12);
        user.RPrewardDebt = userPoint.mul(pool.accRPPerShare).div(1e12);
        updateTotalVotePower(msg.sender, _pid);
        updateVotePool(msg.sender);
        if (pending > 0) {
            safeWETHTransfer(msg.sender, pending, true);
        }
        pool.lpToken.safeTransfer(address(msg.sender), _amount);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY. 30% penalty fees
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 oldUserAmount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        if(_pid == 0 && voted[msg.sender]) {
            LPstake.redeemVote(msg.sender, userInfo[0][msg.sender].votedID);
        }
        pool.lpToken.safeTransfer(address(msg.sender), oldUserAmount.mul(700).div(1000));
        pool.lpToken.safeTransfer(owner(), oldUserAmount.mul(300).div(1000));

        emit EmergencyWithdraw(msg.sender, _pid, oldUserAmount);
    }

    // Safe WETH transfer function, just in case if rounding error causes pool to not have enough WETHs.
    function safeWETHTransfer(address _to, uint256 _amount, bool _acceptLoss) internal {
        uint256 WETHBal = WETH.balanceOf(address(this));
        if (_amount > WETHBal) {
            if(_acceptLoss){
                pendingClaims[_to] = pendingClaims[_to].add(_amount.sub(WETHBal));
                WETH.transfer(_to, WETHBal);
            }
            else revert WETH_NotSufficient();
        } else {
            WETH.transfer(_to, _amount);
        }
    }

    function updateLPstake(stakingpool _stake) external onlyOwner {
        require(address(LPstake) == address(0), "already set");
        LPstake = _stake;
        emit LPstakeUpdated(address(_stake));
    }

    function updateReward(IERC20 _reward) external onlyOwner {
        WETH = _reward;
        emit RewardUpdated(address(_reward));
    }

    function claimPending(address _user) external {
        uint256 amount = pendingClaims[_user];
        pendingClaims[_user] = 0;
        uint256 prevWETHBal = WETH.balanceOf(address(this));
        safeWETHTransfer(_user, amount, true);
        uint256 afterWETHBal = WETH.balanceOf(address(this));
        emit PendingClaimed(_user, prevWETHBal-afterWETHBal);
    }

    function migrate(address _user) external {
        require(helper != address(0), "helper not set");
        require(msg.sender == helper, "not helper");
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][_user];
        updatePool(0);
        IoldXCONEStaking.UserInfo memory oldUser = oldXCONEStaking.userInfo(0, _user);
        uint256 pendingRPForUser = oldXCONEStaking.pendingRP(0, _user);
        uint256 pendingWETHForUser = oldXCONEStaking.pendingWETH(0, _user);
        user.amount = oldUser.amount;
        user.RPamount = oldUser.RPamount + pendingRPForUser;
        if(pendingWETHForUser > 0) {
            safeWETHTransfer(_user, pendingWETHForUser, false);
        }
        uint256 userPoint = user.amount.add(user.RPamount);
        user.rewardDebt = userPoint.mul(pool.accWETHPerShare).div(1e12);
        user.RPrewardDebt = userPoint.mul(pool.accRPPerShare).div(1e12);
        updateTotalVotePower(msg.sender, 0);
        pool.totalRP = pool.totalRP.add(user.RPamount);
        emit Migrated(_user, user.amount);
    }
}

