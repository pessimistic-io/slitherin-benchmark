// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IStakingCompoundV2.sol";
import "./IMintable.sol";
import "./IBurnable.sol";

contract StakingROLPV2 is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Compound(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token ,uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewRewardPerSecond(uint256[] rewardPerSecond);
    event NewRewardByIndex(uint256 index, uint256 rewardPerSecond);
    event EmergencyRewardWithdraw(address indexed owner, uint256[]  aount);
    event AddReward(address indexed rwToken,  uint256 tokenPerSecond);
    event NewEndTime(uint256 endTime);
    event NewTokenRwByIndex(uint256 index, address rwToken);


    // Info of pool.
    struct PoolInfo {
        uint256 totalStake; // total amount staked on Pool
        uint256 startTime;
        uint256 lastTimeReward; // Last time  that token distribution occurs.
        uint256 rewardEndTime; // The time when token distribution ends.
    }

    struct RewardInfo {
        IERC20Upgradeable rwToken;
        uint256 tokenPerSecond; // Accumulated token per share, times 1e18.
        uint256 accTokenPerShare; //  token tokens distribution per second.
        //uint256 accTokenPerShareDebt;
    }

    struct PendingReward {
        uint256 rewardDebt;
        uint256 rewardPending;
    }

    RewardInfo[] public rewardInfo;
    IERC20Upgradeable public ROLP;
    address public stakeTracker;
    address public stakingCompound;
    // Info of pool.
    PoolInfo public poolInfo;
    // Info of user that stakes tokens.
    mapping(address => uint256) public userAmount;
    mapping(address => mapping(IERC20Upgradeable => PendingReward)) public rewardPending;
    mapping(address => bool) private permission;
    mapping(address => bool) isAddReward;
    uint256[50] private __gap;

    function initialize(address _ROLP) public initializer {
        require(_ROLP != address(0), "zeroAddr");
        ROLP = IERC20Upgradeable(_ROLP);
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
        require(poolInfo.startTime == 0 && poolInfo.totalStake == 0, "Pool created");
        poolInfo = 
            PoolInfo({
                startTime: _startTime,
                lastTimeReward: _startTime,
                totalStake: 0,
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
        uint256 lpSupply = poolInfo.totalStake;
        uint256 accTokenPerShare = rewardInfo[_indexRw].accTokenPerShare;
        if (block.timestamp > poolInfo.lastTimeReward && lpSupply != 0) {
            uint256 multiplier = _getMultiplier(poolInfo.lastTimeReward, block.timestamp, poolInfo.rewardEndTime);
            uint256 tokenReward = multiplier.mul(rewardInfo[_indexRw].tokenPerSecond);
            accTokenPerShare = accTokenPerShare.add((tokenReward.mul(1e18)).div(lpSupply));
        }
        PendingReward memory pendingReward = rewardPending[_user][rewardInfo[_indexRw].rwToken];
        return ((userAmount[_user].mul(accTokenPerShare).div(1e18)).sub(pendingReward.rewardDebt).add(pendingReward.rewardPending));
    }

    function compound(bool[] calldata _isClaim , bool[] calldata _isCompound) external nonReentrant {
        uint256 amountStaked = userAmount[msg.sender];

        updatePool();
        for (uint i = 0;  i < rewardInfo.length; i++) {
            PendingReward storage pendingReward = rewardPending[msg.sender][rewardInfo[i].rwToken];
            uint256 pending = ((amountStaked).mul(rewardInfo[i].accTokenPerShare)).div(1e18).sub(pendingReward.rewardDebt);
            if(IStakingCompoundV2(stakingCompound).getAddrStaking(address(rewardInfo[i].rwToken)) == 1 
                || IStakingCompoundV2(stakingCompound).getAddrStaking(address(rewardInfo[i].rwToken)) == 2 ) {

                if(_isCompound[i]) {
                    rewardInfo[i].rwToken.safeTransfer(stakingCompound, pendingReward.rewardPending.add(pending));
                    if(IStakingCompoundV2(stakingCompound).getAddrStaking(address(rewardInfo[i].rwToken)) == 1) {
                        require(IStakingCompoundV2(stakingCompound).depositRw(msg.sender, pendingReward.rewardPending.add(pending), 1), "compound false");
                        emit Compound(msg.sender, address(rewardInfo[i].rwToken), pendingReward.rewardPending.add(pending));
                        pendingReward.rewardPending = 0;
                    } else {
                        require(IStakingCompoundV2(stakingCompound).depositRw(msg.sender, pendingReward.rewardPending.add(pending), 2), "compound false");
                        emit Compound(msg.sender, address(rewardInfo[i].rwToken), pendingReward.rewardPending.add(pending));
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
            pendingReward.rewardDebt = ((userAmount[msg.sender]).mul(rewardInfo[i].accTokenPerShare)).div(1e18);
        }
    }

    function getPoolInfo()
        public
        view
        returns (
            uint256 startTime,
            uint256 lastTimeReward,
            uint256 totalStake,
            uint256 rewardEndTime
        )
    {
        return (
            poolInfo.startTime,
            poolInfo.lastTimeReward,
            poolInfo.totalStake,
            poolInfo.rewardEndTime
        );
    }

    function getUserInfo( address _user)
        public
        view
        returns (
            uint256 amount
        )
    {
        return (
            userAmount[_user]
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
        uint256 lpSupply = poolInfo.totalStake;
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
    function deposit(uint256 _amount) external nonReentrant {
        require(_amount > 0, "deposit: amount > 0");
        uint256 amountStaked = userAmount[msg.sender];
        updatePool();
       
        for (uint i = 0;  i < rewardInfo.length; i++) {
            PendingReward storage pendingReward = rewardPending[msg.sender][rewardInfo[i].rwToken];
            uint256 pending = (amountStaked.mul(rewardInfo[i].accTokenPerShare).div(1e18)).sub(pendingReward.rewardDebt);
            if (pending > 0) {
                pendingReward.rewardPending = pendingReward.rewardPending.add(pending);
            }
            pendingReward.rewardDebt = ((amountStaked.add(_amount)).mul(rewardInfo[i].accTokenPerShare)).div(1e18);
        }
      
        IMintable(stakeTracker).mint(address(msg.sender), _amount);

        ROLP.safeTransferFrom(address(msg.sender), address(this), _amount);
        userAmount[msg.sender] = amountStaked.add(_amount);
        poolInfo.totalStake= poolInfo.totalStake.add(_amount);
        emit Deposit(msg.sender, address(ROLP), _amount);
        
    }

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw
     */
    function withdraw(uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo;
        uint256 amountStaked = userAmount[msg.sender];
        require(_amount > 0, "withdraw: amount > 0");
    
        require(amountStaked >= _amount, "withdraw: amount not enough");
       

        updatePool();
        for (uint i = 0;  i < rewardInfo.length; i++) {
            PendingReward storage pendingReward = rewardPending[msg.sender][rewardInfo[i].rwToken];
            uint256 pending = ((amountStaked).mul(rewardInfo[i].accTokenPerShare).div(1e18)).sub(pendingReward.rewardDebt);
            if (pending > 0) {
                pendingReward.rewardPending = pendingReward.rewardPending.add(pending);
            }
            pendingReward.rewardDebt = ((amountStaked.sub(_amount)).mul(rewardInfo[i].accTokenPerShare)).div(1e18);
        }

        IBurnable(stakeTracker).burn(address(msg.sender), _amount);

        ROLP.safeTransfer(address(msg.sender), _amount);
        userAmount[msg.sender] = amountStaked.sub(_amount);
        pool.totalStake = pool.totalStake.sub(_amount);
        emit Withdraw(msg.sender, address(ROLP), _amount);
    }

    function claim(bool[] calldata _isClaim) external nonReentrant {
        uint256 amountStaked = userAmount[msg.sender];
        updatePool();
        for (uint i = 0;  i < rewardInfo.length; i++) {
            PendingReward storage pendingReward = rewardPending[msg.sender][rewardInfo[i].rwToken];
            uint256 pending = (amountStaked.mul(rewardInfo[i].accTokenPerShare).div(1e18)).sub(pendingReward.rewardDebt);
            if(_isClaim[i]) {
                uint256 claimAmount = pendingReward.rewardPending.add(pending);
                if (claimAmount > 0) {
                    rewardInfo[i].rwToken.transfer(msg.sender, claimAmount);
                    pendingReward.rewardPending = 0;
                }
            } else {
                pendingReward.rewardPending = pendingReward.rewardPending.add(pending);
            }
            pendingReward.rewardDebt = ((amountStaked).mul(rewardInfo[i].accTokenPerShare)).div(1e18);
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
        
        for (uint i = 0; i<_rewardPerSeconds.length; i++) {
            rewardInfo[i].tokenPerSecond = _rewardPerSeconds[i];
        }

        emit NewRewardPerSecond(_rewardPerSeconds);
    }

    function updateRewardByIndex(uint256 _rewardPerSecond, uint256 _index) external onlyOwner {
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

    function setStakeTracker(address _addr) external onlyOwner {
        stakeTracker = _addr;
    }

    function setPermission(address _permission, bool _enabled) external onlyOwner {
        permission[_permission] = _enabled;
    }

    function setStakingCompound(address _address) external onlyOwner {
        stakingCompound = _address;
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
        for (uint i = 0; i<_amount.length; i++) {
            rewardInfo[i].rwToken.transfer(address(msg.sender), _amount[i]);
        }
        emit EmergencyRewardWithdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public nonReentrant {
        PoolInfo storage pool = poolInfo;
        uint256 amountStaked = userAmount[msg.sender];
        userAmount[msg.sender] = 0;
        ROLP.safeTransfer(address(msg.sender), amountStaked);
        IBurnable(stakeTracker).burn(address(msg.sender), amountStaked);
        pool.totalStake -= amountStaked;
        emit EmergencyWithdraw(msg.sender, amountStaked);

        for (uint i = 0;  i < rewardInfo.length; i++) {
            PendingReward storage pendingReward = rewardPending[msg.sender][rewardInfo[i].rwToken];
            pendingReward.rewardDebt = 0;
            pendingReward.rewardPending = 0;
        }
    }
}

