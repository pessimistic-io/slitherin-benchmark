// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./ReentrancyGuard.sol";
import "./Context.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./draft-IERC20Permit.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

interface token is IERC20 {
    function mint(address recipient, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;
}

contract LPstaking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 vote;
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt;
        uint256 xCONErewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of CONEs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accCONEPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accCONEPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        bool voteable;
        uint256 allocPoint; // How many allocation points assigned to this pool. CONEs to distribute per block.
        uint256 lastRewardTime; // Last block time that CONEs distribution occurs.
        uint256 accCONEPerShare; // Accumulated CONEs per share, times 1e12. See below.
        uint256 accxCONEPerShare; // Accumulated xCONEs per share, times 1e12. See below.
    }

    token public immutable CONE;
    token public immutable xCONE;

    address public stakepool;
    // CONE tokens created per block.
    uint256 public CONEPerSecond;
    uint256 public xCONEPerSecond;

    uint256 public totalCONEdistributed = 0;
    uint256 public xCONEdistributed = 0;

    // set a max CONE per second, which can never be higher than 1 per second
    uint256 public constant maxCONEPerSecond = 1e18;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block time when CONE mining starts.
    uint256 public immutable startTime;

    bool public withdrawable = false;

    mapping(IERC20 => mapping(address => uint256)) public pendingClaims;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event RewardsEarned(
        address indexed user,
        uint256 amount,
        IERC20 indexed token
    );
    event StakePoolUpdated(address indexed pool);

    constructor(
        uint256 _CONEPerSecond,
        uint256 _xCONEPerSecond,
        uint256 _startTime,
        address _cone,
        address _xCone
    ) {
        CONEPerSecond = _CONEPerSecond;
        xCONEPerSecond = _xCONEPerSecond;
        startTime = _startTime;
        CONE = token(_cone);
        xCONE = token(_xCone);
    }

    function openWithdraw() external onlyOwner {
        withdrawable = true;
    }

    function closeWithdraw() external onlyOwner {
        withdrawable = false;
    }

    function supplyRewards(
        uint256 _amount,
        IERC20 _rewardToken
    ) external onlyOwner {
        require(
            _rewardToken == xCONE || _rewardToken == CONE,
            "Not a valid reward token"
        );
        _rewardToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
    }

    // Update the given pool's CONE allocation point. Can only be called by the owner.
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

        if (_amount > user.vote) {
            uint256 increaseAmount = _amount.sub(user.vote);
            user.vote = _amount;
            increaseAllocation(_pid, increaseAmount);
        } else {
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

    // Changes CONE token reward per second, with a cap of maxCONE per second
    // Good practice to update pools without messing up the contract
    function setCONEPerSecond(uint256 _CONEPerSecond) external onlyOwner {
        require(
            _CONEPerSecond <= maxCONEPerSecond,
            "setCONEPerSecond: too many CONEs!"
        );

        // This MUST be done or pool rewards will be calculated with new CONE per second
        // This could unfairly punish small pools that dont have frequent deposits/withdraws/harvests
        massUpdatePools();

        CONEPerSecond = _CONEPerSecond;
    }

    function setxCONEPerSecond(uint256 _xCONEPerSecond) external onlyOwner {
        require(
            _xCONEPerSecond <= maxCONEPerSecond,
            "setCONEPerSecond: too many CONEs!"
        );

        // This MUST be done or pool rewards will be calculated with new CONE per second
        // This could unfairly punish small pools that dont have frequent deposits/withdraws/harvests
        massUpdatePools();

        xCONEPerSecond = _xCONEPerSecond;
    }

    function checkForDuplicate(IERC20 _lpToken) internal view {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; ++_pid) {
            require(
                poolInfo[_pid].lpToken != _lpToken,
                "add: pool already exists!!!!"
            );
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken) external onlyOwner {
        checkForDuplicate(_lpToken); // ensure you cant add duplicate pools

        massUpdatePools();

        uint256 lastRewardTime = block.timestamp > startTime
            ? block.timestamp
            : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                voteable: true,
                allocPoint: _allocPoint,
                lastRewardTime: lastRewardTime,
                accCONEPerShare: 0,
                accxCONEPerShare: 0
            })
        );
    }

    // Update the given pool's CONE allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) external onlyOwner {
        massUpdatePools();

        totalAllocPoint =
            totalAllocPoint -
            poolInfo[_pid].allocPoint +
            _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function setVotePermission(uint256 _pid, bool _vote) external onlyOwner {
        massUpdatePools();

        poolInfo[_pid].voteable = _vote;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public view returns (uint256) {
        _from = _from > startTime ? _from : startTime;
        if (_to < startTime) {
            return 0;
        }
        return _to - _from;
    }

    // View function to see pending CONEs on frontend.
    function pendingCONE(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accCONEPerShare = pool.accCONEPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 CONEReward = multiplier
                .mul(CONEPerSecond)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accCONEPerShare = accCONEPerShare.add(
                CONEReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accCONEPerShare).div(1e12).sub(user.rewardDebt);
    }

    function pendingxCONE(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accxCONEPerShare = pool.accxCONEPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 xCONEReward = multiplier
                .mul(xCONEPerSecond)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accxCONEPerShare = accxCONEPerShare.add(
                xCONEReward.mul(1e12).div(lpSupply)
            );
        }
        return
            user.amount.mul(accxCONEPerShare).div(1e12).sub(
                user.xCONErewardDebt
            );
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
        uint256 multiplier = getMultiplier(
            pool.lastRewardTime,
            block.timestamp
        );
        uint256 CONEReward = multiplier
            .mul(CONEPerSecond)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
        uint256 xCONEReward = multiplier
            .mul(xCONEPerSecond)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);

        pool.accCONEPerShare = pool.accCONEPerShare.add(
            CONEReward.mul(1e12).div(lpSupply)
        );
        pool.accxCONEPerShare = pool.accxCONEPerShare.add(
            xCONEReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens to MasterChef for CONE allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accCONEPerShare).div(1e12).sub(
            user.rewardDebt
        );
        uint256 EsPending = user
            .amount
            .mul(pool.accxCONEPerShare)
            .div(1e12)
            .sub(user.xCONErewardDebt);

        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accCONEPerShare).div(1e12);
        user.xCONErewardDebt = user.amount.mul(pool.accxCONEPerShare).div(1e12);

        if (pending > 0 || EsPending > 0) {
            safeRewardTransfer(msg.sender, pending, CONE);
            safeRewardTransfer(msg.sender, EsPending, xCONE);
        }
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");
        require(withdrawable, "withdraw not opened");

        updatePool(_pid);

        uint256 pending = user.amount.mul(pool.accCONEPerShare).div(1e12).sub(
            user.rewardDebt
        );
        uint256 EsPending = user
            .amount
            .mul(pool.accxCONEPerShare)
            .div(1e12)
            .sub(user.xCONErewardDebt);

        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accCONEPerShare).div(1e12);
        user.xCONErewardDebt = user.amount.mul(pool.accxCONEPerShare).div(1e12);

        if (pending > 0 || EsPending > 0) {
            safeRewardTransfer(msg.sender, pending, CONE);
            safeRewardTransfer(msg.sender, EsPending, xCONE);
        }
        pool.lpToken.safeTransfer(address(msg.sender), _amount);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // send reward tokens to users
    function safeRewardTransfer(
        address _to,
        uint256 _amount,
        IERC20 _rewardToken
    ) internal {
        uint256 rewardBal = _rewardToken.balanceOf(address(this));
        if (_amount > rewardBal) {
            pendingClaims[_rewardToken][_to] = pendingClaims[_rewardToken][_to]
                .add(_amount.sub(rewardBal));
            _rewardToken.safeTransfer(_to, rewardBal);
            if (_rewardToken == xCONE) xCONEdistributed += rewardBal;
            else totalCONEdistributed += rewardBal;
            // for the right amount of rewards earned event
            _amount = rewardBal;
        } else {
            _rewardToken.safeTransfer(_to, _amount);
            if (_rewardToken == xCONE) xCONEdistributed += _amount;
            else totalCONEdistributed += _amount;
        }
        emit RewardsEarned(_to, _amount, _rewardToken);
    }

    // claim pending reward tokens
    function claimReward(IERC20 _rewardToken) external {
        require(
            _rewardToken == xCONE || _rewardToken == CONE,
            "Not a valid reward token"
        );
        uint256 claimAmount = pendingClaims[_rewardToken][msg.sender];
        require(claimAmount > 0, "nothing to claim");
        require(
            _rewardToken.balanceOf(address(this)) >= claimAmount,
            "not enough tokens in contract"
        );
        pendingClaims[_rewardToken][msg.sender] = 0;
        _rewardToken.safeTransfer(msg.sender, claimAmount);
        if (_rewardToken == xCONE) xCONEdistributed += claimAmount;
        else totalCONEdistributed += claimAmount;
        emit RewardsEarned(msg.sender, claimAmount, _rewardToken);
    }

    function updateStakePool(address _pool) external onlyOwner {
        stakepool = _pool;
        emit StakePoolUpdated(_pool);
    }
}

