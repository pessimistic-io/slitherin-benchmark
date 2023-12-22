// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IMintable.sol";
import "./IBurnable.sol";

contract StakingDualTokenV2 is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token ,uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amountRosx, uint256 amountERosx);
    event NewRewardPerSecond(uint256[] rewardPerSecond);
    event NewRewardByIndex(uint256 index, uint256 rewardPerSecond);
    event EmergencyRewardWithdraw(address indexed owner, uint256[]  aount);
    event AddReward(address indexed rwToken,  uint256 tokenPerSecond);
    event NewEndTime(uint256 endTime);
    event NewTokenRwByIndex(uint256 index, address rwToken);

    // Info of each user.
    struct UserInfo {
        uint256 amountRosx; // How many tokens the user has provided.
        uint256 amountERosx;
        uint256 point;
        uint256 lock;
    }

    // Info of pool.
    struct PoolInfo {
        uint256 totalStakeRosx; // total amount staked on Pool
        uint256 totalStakeERosx;
        uint256 startTime;
        uint256 lastTimeReward; // Last time  that token distribution occurs.
        uint256 totalPoint;
        uint256 rewardEndTime; // The time when token distribution ends.
    }

    struct RewardInfo {
        IERC20Upgradeable rwToken;
        uint256 tokenPerSecond; // Accumulated token per share, times 1e18.
        uint256 accTokenPerShare; //  token tokens distribution per second.
    }

    struct PendingReward {
        uint256 rewardDebt;
        uint256 rewardPending;
    }

    RewardInfo[] public rewardInfo;
    IERC20Upgradeable public ROSX;
    IERC20Upgradeable public EROSX;
    address public stakeTracker;
    address public feeAddr; 
    uint256 public claimFee;
    // Info of pool.
    PoolInfo public poolInfo;
    // Info of user that stakes tokens.
    mapping(address => UserInfo) public userInfo;
    mapping(address => uint256) public addrStake;
    mapping(address => mapping(IERC20Upgradeable => PendingReward)) public rewardPending;
    mapping(address => bool) private permission;
    mapping(address=> bool) isAddReward;
    uint256[50] private __gap;

    function initialize(address _ROSX, address _EROSX) public initializer {
        require(address(_ROSX) != address(0) && address(_EROSX) != address(0), "zeroAddr");
        ROSX = IERC20Upgradeable(_ROSX);
        addrStake[address(_ROSX)] = 1;
        EROSX = IERC20Upgradeable(_EROSX);
        addrStake[address(_EROSX)] = 2;
        __Ownable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {
        
    }

    modifier onlyPermission() {
        require(permission[msg.sender], "NOT_THE_PERMISSION");
        _;
    }

    // Create a new pool. Can only be called by the owner.
    function create(
        uint256 _startTime,
        uint256 _rewardEndTime
    ) public onlyOwner {
        require(poolInfo.startTime == 0 && poolInfo.totalStakeRosx == 0 && poolInfo.totalStakeERosx == 0, "Pool created");
        poolInfo = 
            PoolInfo({
                startTime: _startTime,
                lastTimeReward: _startTime,
                totalStakeRosx: 0,
                totalStakeERosx: 0,
                totalPoint: 0,
                rewardEndTime: _rewardEndTime
            });
    }

    function addReward(IERC20Upgradeable _rwToken,  uint256 _tokenPerSecond) public onlyOwner {
        require(!isAddReward[address(_rwToken)], "Duplicate reward");
        updatePool(); 
        rewardInfo.push(RewardInfo ({
            rwToken: _rwToken,
            tokenPerSecond: _tokenPerSecond,
            accTokenPerShare: 0
        }));
        isAddReward[address(_rwToken)] = true;
        emit AddReward(address(_rwToken), _tokenPerSecond);
    }

    /*
     * @notice Return reward multiplier over the given _from to _to time.
     * @param _from: time to start
     * @param _to: time to finish
     * @param _rewardEndTime: time end to reward
     */
    function _getMultiplier(
        uint256 _from,
        uint256 _to,
        uint256 _rewardEndTime
    ) internal  pure returns (uint256) {
        if (_to <= _rewardEndTime) {
            return _to - _from;
        } else if (_from >= _rewardEndTime) {
            return 0;
        } else {
            return _rewardEndTime - _from;
        }
    }

    // View function to see pending token on frontend.
    function pendingToken(address _user, uint256  _indexRw) external view returns (uint256 pending) {
        uint256 lpSupply = poolInfo.totalStakeRosx.add(poolInfo.totalStakeERosx).add(poolInfo.totalPoint);
        uint256 accTokenPerShare = rewardInfo[_indexRw].accTokenPerShare;
        if (block.timestamp > poolInfo.lastTimeReward && lpSupply != 0) {
            uint256 multiplier = _getMultiplier(poolInfo.lastTimeReward, block.timestamp, poolInfo.rewardEndTime);
            uint256 tokenReward = multiplier.mul(rewardInfo[_indexRw].tokenPerSecond);
            accTokenPerShare = accTokenPerShare.add((tokenReward.mul(1e18)).div(lpSupply));
        }
        PendingReward memory pendingReward = rewardPending[_user][rewardInfo[_indexRw].rwToken];
        UserInfo memory user = userInfo[_user];
        return (((user.amountRosx.add(user.amountERosx).add(user.point)).mul(accTokenPerShare).div(1e18)).sub(pendingReward.rewardDebt).add(pendingReward.rewardPending));
    }

    function compound(bool[] calldata _isClaim , bool[] calldata _isCompound) external nonReentrant {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        uint256 amountRosxBf = user.amountRosx;
        uint256 amountERosxBf = user.amountERosx;
        updatePool();
        for (uint i = 0;  i < rewardInfo.length; i++) {
            PendingReward storage pendingReward = rewardPending[msg.sender][rewardInfo[i].rwToken];
            uint256 pending = ((amountRosxBf.add(amountERosxBf).add(user.point)).mul(rewardInfo[i].accTokenPerShare)).div(1e18).sub(pendingReward.rewardDebt);
            if(addrStake[address(rewardInfo[i].rwToken)] == 1 || addrStake[address(rewardInfo[i].rwToken)] == 2 ) {
                if(_isCompound[i]) {
                    IMintable(stakeTracker).mint(address(msg.sender), pendingReward.rewardPending.add(pending));
                    if(addrStake[address(rewardInfo[i].rwToken)] == 1) {
                        user.amountRosx = user.amountRosx.add(pendingReward.rewardPending).add(pending);
                        pool.totalStakeRosx = pool.totalStakeRosx.add(pendingReward.rewardPending).add(pending);
                        emit Deposit(msg.sender, address(ROSX), pendingReward.rewardPending.add(pending));
                        pendingReward.rewardPending = 0;
                    } else {
                        user.amountERosx = user.amountERosx.add(pendingReward.rewardPending).add(pending);
                        pool.totalStakeERosx = pool.totalStakeERosx.add(pendingReward.rewardPending).add(pending);
                        emit Deposit(msg.sender, address(EROSX), pendingReward.rewardPending.add(pending));
                        pendingReward.rewardPending = 0;
                    }
                } else if(_isClaim[i]) {
                    rewardInfo[i].rwToken.transfer(msg.sender, pendingReward.rewardPending.add(pending));
                    pendingReward.rewardPending = 0;
                    
                } else {
                    pendingReward.rewardPending =pendingReward.rewardPending.add(pending);
                }

            } else {
                if(_isClaim[i]) {
                    rewardInfo[i].rwToken.transfer(msg.sender, pendingReward.rewardPending.add(pending));
                    pendingReward.rewardPending = 0;
                } else {
                    pendingReward.rewardPending = pendingReward.rewardPending.add(pending);
                }
            }
        }

        for (uint i = 0;  i < rewardInfo.length; i++) {
            PendingReward storage pendingReward = rewardPending[msg.sender][rewardInfo[i].rwToken];
            pendingReward.rewardDebt = ((user.amountRosx.add(user.amountERosx).add(user.point)).mul(rewardInfo[i].accTokenPerShare)).div(1e18);
        }
    }

    function getPoolInfo()
        public
        view
        returns (
            uint256 startTime,
            uint256 lastTimeReward,
            uint256 totalStakeRosx,
            uint256 totalStakeERosx,
            uint256 rewardEndTime,
            uint256 totalPoint
        )
    {
        return (
            poolInfo.startTime,
            poolInfo.lastTimeReward,
            poolInfo.totalStakeRosx,
            poolInfo.totalStakeERosx,
            poolInfo.rewardEndTime,
            poolInfo.totalPoint
        );
    }

    function getUserInfo( address _user)
        public
        view
        returns (
            uint256 amountRosx,
            uint256 amountERosx,
            uint256 point,
            uint256 lockAmount
        )
    {
        return (
            userInfo[_user].amountRosx,
            userInfo[_user].amountERosx,
            userInfo[_user].point,
            userInfo[_user].lock
        );
    }

    function getTime() public view returns (uint256 time) {
        return block.timestamp;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() internal  {
        //PoolInfo storage pool = poolInfo;
        if (block.timestamp <= poolInfo.lastTimeReward) {
            return;
        }
        uint256 lpSupply = poolInfo.totalStakeRosx.add(poolInfo.totalStakeERosx).add(poolInfo.totalPoint);
        if (lpSupply == 0) {
            poolInfo.lastTimeReward = block.timestamp;
            for(uint k=0; k<rewardInfo.length; k++) {
                rewardInfo[k].accTokenPerShare = 0;
            }
            return;
        }
        uint256 multiplier = _getMultiplier(poolInfo.lastTimeReward, block.timestamp, poolInfo.rewardEndTime);
        for(uint j=0; j<rewardInfo.length; j++) {
            uint256 tokenReward = multiplier.mul(rewardInfo[j].tokenPerSecond);
            rewardInfo[j].accTokenPerShare = rewardInfo[j].accTokenPerShare.add((tokenReward.mul(1e18)).div(lpSupply));
        }
        poolInfo.lastTimeReward = block.timestamp;
    }

    /*
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param __index: index of pool 1: 
     * @param _amount: amount to deposit
     */
    function deposit(uint256 _amount, uint256 _index) external nonReentrant {
        require(_amount > 0, "deposit: amount > 0");
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
       
        for (uint i = 0;  i < rewardInfo.length; i++) {
            PendingReward storage pendingReward = rewardPending[msg.sender][rewardInfo[i].rwToken];
            uint256 pending = ((user.amountRosx.add(user.amountERosx).add(user.point)).mul(rewardInfo[i].accTokenPerShare).div(1e18)).sub(pendingReward.rewardDebt);
            if (pending > 0) {
                pendingReward.rewardPending = pendingReward.rewardPending.add(pending);
            }
            pendingReward.rewardDebt = ((user.amountRosx.add(user.amountERosx).add(user.point).add(_amount)).mul(rewardInfo[i].accTokenPerShare)).div(1e18);
        }
      
        IMintable(stakeTracker).mint(address(msg.sender), _amount);
        if(_index == 1) {
            ROSX.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amountRosx = user.amountRosx.add(_amount);
            poolInfo.totalStakeRosx = poolInfo.totalStakeRosx.add(_amount);
            emit Deposit(msg.sender, address(ROSX), _amount);
        } else {
            EROSX.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amountERosx = user.amountERosx.add(_amount);
            poolInfo.totalStakeERosx = poolInfo.totalStakeERosx.add(_amount);
            emit Deposit(msg.sender, address(EROSX), _amount);
        }
        
    }

    function getAddrStaking(address _addr) external view returns(uint256) {
        return addrStake[_addr];
    }


    function depositRw(address addr, uint256 _amount, uint256 _index) external onlyPermission returns (bool) {
        require(_amount > 0, "deposit: amount > 0");
        UserInfo storage user = userInfo[addr];
        updatePool();
       
        for (uint i = 0;  i < rewardInfo.length; i++) {
            PendingReward storage pendingReward = rewardPending[addr][rewardInfo[i].rwToken];
            uint256 pending = ((user.amountRosx.add(user.amountERosx).add(user.point)).mul(rewardInfo[i].accTokenPerShare).div(1e18)).sub(pendingReward.rewardDebt);
            if (pending > 0) {
                pendingReward.rewardPending = pendingReward.rewardPending.add(pending);
            }
            pendingReward.rewardDebt = ((user.amountRosx.add(user.amountERosx).add(user.point).add(_amount)).mul(rewardInfo[i].accTokenPerShare)).div(1e18);
        }
      
        IMintable(stakeTracker).mint(address(addr), _amount);
        if(_index == 1) {
            user.amountRosx = user.amountRosx.add(_amount);
            poolInfo.totalStakeRosx = poolInfo.totalStakeRosx.add(_amount);
            emit Deposit(addr, address(ROSX), _amount);
        } else {
            user.amountERosx = user.amountERosx.add(_amount);
            poolInfo.totalStakeERosx = poolInfo.totalStakeERosx.add(_amount);
            emit Deposit(addr, address(EROSX), _amount);
        }
        return true;
    }

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw
     */
    function withdraw(uint256 _amount, uint256 _index) public nonReentrant {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        require(_amount > 0, "withdraw: amount > 0");
        if (_index == 1) {
            require(user.amountRosx >= user.lock.add(_amount), "withdraw: amount not enough");
        } else {
            require(user.amountERosx >= _amount, "withdraw: amount not enough");
        }

        updatePool();
        for (uint i = 0;  i < rewardInfo.length; i++) {
            PendingReward storage pendingReward = rewardPending[msg.sender][rewardInfo[i].rwToken];
            uint256 pending = ((user.amountRosx.add(user.amountERosx).add(user.point)).mul(rewardInfo[i].accTokenPerShare).div(1e18)).sub(pendingReward.rewardDebt);
            if (pending > 0) {
                pendingReward.rewardPending = pendingReward.rewardPending.add(pending);
            }
            pendingReward.rewardDebt = ((user.amountRosx.add(user.amountERosx).add(user.point).sub(_amount)).mul(rewardInfo[i].accTokenPerShare)).div(1e18);
        }

        IBurnable(stakeTracker).burn(address(msg.sender), _amount);
        if (_index == 1) {
            ROSX.safeTransfer(address(msg.sender), _amount);
            user.amountRosx = user.amountRosx.sub(_amount);
            pool.totalStakeRosx = pool.totalStakeRosx.sub(_amount);
            emit Withdraw(msg.sender, address(ROSX), _amount);
        } else {
            EROSX.safeTransfer(address(msg.sender), _amount);
            user.amountERosx = user.amountERosx.sub(_amount);
            pool.totalStakeERosx = pool.totalStakeERosx.sub(_amount);
            emit Withdraw(msg.sender, address(EROSX), _amount);
        }
    }

    function claim(bool[] calldata _isClaim) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        for (uint i = 0;  i < rewardInfo.length; i++) {
            PendingReward storage pendingReward = rewardPending[msg.sender][rewardInfo[i].rwToken];
            uint256 pending = ((user.amountRosx.add(user.amountERosx).add(user.point)).mul(rewardInfo[i].accTokenPerShare).div(1e18)).sub(pendingReward.rewardDebt);
            if(_isClaim[i]) {
                uint256 claimAmount = pendingReward.rewardPending.add(pending);
                if (claimAmount> 0) {
                    if(claimFee > 0) {
                        uint256 fee = (claimFee.mul(claimAmount)).div(100000);
                        claimAmount = claimAmount.sub(fee);
                        rewardInfo[i].rwToken.transfer(feeAddr, fee);
                    }
                    rewardInfo[i].rwToken.transfer(msg.sender, claimAmount);
                    pendingReward.rewardPending = 0;
                }
            } else {
                pendingReward.rewardPending = pendingReward.rewardPending.add(pending);
            }
            pendingReward.rewardDebt = ((user.amountRosx.add(user.amountERosx).add(user.point)).mul(rewardInfo[i].accTokenPerShare)).div(1e18);
        }
    }

    /*
     * @notice Update reward per second, start time , endTime 
     * @dev Only callable by owner.
     * @param _startTime: start time reward pool
     * @param _endTime: end time reward pool
     * @param _rewardPerSecond: the reward per second
     */
    function updateReward(uint256 _startTime, uint256 _endTime, uint256[] calldata _rewardPerSeconds) external onlyOwner {
        require(block.timestamp >= poolInfo.rewardEndTime, "Time invalid");
        updatePool();

        poolInfo.startTime = _startTime;
        poolInfo.rewardEndTime = _endTime;
        poolInfo.lastTimeReward = _startTime;
        for (uint i = 0; i < _rewardPerSeconds.length; i++) {
            rewardInfo[i].tokenPerSecond = _rewardPerSeconds[i];
        }
        emit NewRewardPerSecond(_rewardPerSeconds);
    }

    function updateRewardByIndex(uint256  _rewardPerSecond, uint256 _index) external onlyOwner {
        updatePool();
        rewardInfo[_index].tokenPerSecond = _rewardPerSecond;
        emit NewRewardByIndex(_index, _rewardPerSecond);
    }

    function updateEndTime(uint256 _endTime) external onlyOwner {
        updatePool();
        require(_endTime >= poolInfo.lastTimeReward, "Time invalid");
        poolInfo.rewardEndTime = _endTime;
        emit NewEndTime(_endTime);
    }

    function updateTokenRewardByIndex(IERC20Upgradeable _rwToken, uint256 _index) external onlyOwner {
        rewardInfo[_index].rwToken = _rwToken;
        emit NewTokenRwByIndex(_index, address(_rwToken));
    }

    function setClaimFee(uint256 _claimFee) external onlyOwner {
        claimFee = _claimFee;
    }

    function updatePointUsers(address[] calldata _users, 
            uint256[] calldata _points, 
            uint256 _totalPoint) 
            external 
            onlyPermission 
    {
        updatePool();
        poolInfo.totalPoint = _totalPoint;
        for (uint i = 0; i < _users.length; i++) {
            for(uint j=0; j<rewardInfo.length; j++) {
                UserInfo storage user = userInfo[msg.sender];
                PendingReward storage pendingReward = rewardPending[_users[i]][rewardInfo[j].rwToken];
                uint256 pending = ((user.amountRosx.add(user.amountERosx).add(user.point)).mul(rewardInfo[i].accTokenPerShare).div(1e18)).sub(pendingReward.rewardDebt);
                if (pending > 0) {
                    pendingReward.rewardPending =   pendingReward.rewardPending.add(pending);
                }
                pendingReward.rewardDebt = ((user.amountRosx.add(user.amountERosx).add(user.point).add(_points[i])).mul(rewardInfo[i].accTokenPerShare)).div(1e18);
                user.point = _points[i];
            }
        }
    }

    function lock(address _addr, uint256 _amount) external onlyPermission returns (bool) {
        UserInfo storage user = userInfo[_addr];

        if(user.lock + _amount <= user.amountRosx) {
             user.lock += _amount;
            return true;
        }
        return false;
    }

    function unLock(address _addr, uint256 _amount) external onlyPermission returns (bool) {
        UserInfo storage user = userInfo[_addr];
        if(user.lock >= _amount) {
            user.lock -= _amount;
            return true;
        }
        return false;
    }

    function setStakeTracker(address _addr) external onlyOwner {
        stakeTracker = _addr;
    }

    function setPermission(address _permission, bool _enabled) external onlyOwner {
        permission[_permission] = _enabled;
    }

    function setFeeAddress(address _feeAddr) external onlyOwner {
        feeAddr = _feeAddr;
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner
     */
    function stopReward() external onlyOwner {
        poolInfo.rewardEndTime = block.timestamp;
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(uint256[] calldata _amount) external onlyOwner {
        for (uint i = 0; i < _amount.length; i++) {
            rewardInfo[i].rwToken.transfer(address(msg.sender), _amount[i]);
        }

        emit EmergencyRewardWithdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {

        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];

        ROSX.safeTransfer(address(msg.sender), (user.amountRosx -user.lock));
        EROSX.safeTransfer(address(msg.sender), user.amountERosx);

        IBurnable(stakeTracker).burn(address(msg.sender), user.amountRosx - user.lock + user.amountERosx);

        
        pool.totalStakeRosx -= (user.amountRosx - user.lock);
        pool.totalStakeERosx -= user.amountERosx;

        emit EmergencyWithdraw(msg.sender, user.amountRosx -user.lock, user.amountERosx);

        pool.totalPoint -= user.point;
        user.amountRosx = user.lock;
        user.amountERosx = 0;
        user.point = 0;
        for (uint i = 0;  i < rewardInfo.length; i++) {
            PendingReward storage pendingReward = rewardPending[msg.sender][rewardInfo[i].rwToken];
            pendingReward.rewardDebt = 0;
            pendingReward.rewardPending = 0;
        }
    }
}

