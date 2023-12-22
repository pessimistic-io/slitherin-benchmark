// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./EnumerableSet.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

contract RanbasedMaster {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint amount;
        uint rewardDebt;
        uint lastClaimBlock;
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint allocPoint;
        uint lastRewardBlock;
        uint accRanbPerShare;
    }

    IERC20 ranbased;

    uint public ranbPerBlock = 1e4;
    PoolInfo[] public poolInfo;
    mapping(uint => mapping(address => UserInfo)) public userInfo;
    uint public totalAllocPoint = 0;
    address controller;
    uint public startBlock;

    // Events
    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    
    modifier onlyController() {
        require(msg.sender == controller);
        _;
    }

    constructor (
        address _ranb,
        uint _startBlock
    ) {
        ranbased =  IERC20(_ranb);
        startBlock = _startBlock;
        controller = msg.sender;
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    function add(
        uint _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyController {

        if (_withUpdate) {
            massUpdatePools();
        }

        uint lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRanbPerShare: 0
            })
        );
    }
    function setController(address _addr) external {
        controller = _addr;        
    }
    function set(
        uint _pid,
        uint _allocPoint,
        bool _withUpdate
    ) public onlyController {
        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function getMultiplier(uint _from, uint _to) private view returns (uint) {
        uint _blockCount = _to.sub(_from);
        return ranbPerBlock.mul(_blockCount);
    }

    function pendingRanb(uint _pid, address _user)
        external
        view
        returns (uint)
    {
        if(poolInfo.length == 0) return 0;

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint accRanbPerShare = pool.accRanbPerShare;
        uint lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint ranbReward = multiplier
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accRanbPerShare = accRanbPerShare.add(
                ranbReward
                .mul(1e12)
                .div(lpSupply)
            );
        }
        return user.amount.mul(accRanbPerShare)
        .div(1e12)
        .sub(user.rewardDebt);
    }

    function massUpdatePools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint _pid) public {
        if(startBlock == 0) {
            return;
        }

        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        
        if(ranbased.balanceOf(address(this)) < ranbPerBlock ){
           return;
        }

        uint multiplier = getMultiplier(pool.lastRewardBlock, block.number);

        uint ranbReward = multiplier
            .mul(pool.allocPoint)
            .div(totalAllocPoint);

        pool.accRanbPerShare = pool.accRanbPerShare.add(
            ranbReward
            .mul(1e12)
            .div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }
    
    function deposit(uint _pid) public {
        require(startBlock > 0, "not activated yet.!");
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint _amount = pool.lpToken.balanceOf(msg.sender);

        updatePool(_pid);
        if (user.amount > 0) {
            uint pending = user
                .amount
                .mul(pool.accRanbPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
                
            if (pending > 0) {
                ranbased.transfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
        }
        user.lastClaimBlock = block.number;
        user.rewardDebt = user.amount.mul(pool.accRanbPerShare).div(1e12);

        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint _amount = user.amount;
        updatePool(_pid);
        uint pending = user.amount.mul(pool.accRanbPerShare)
        .div(1e12)
        .sub(user.rewardDebt);

        if (pending > 0) {
            ranbased.transfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRanbPerShare).div(1e12);

        user.lastClaimBlock = block.number;

        emit Withdraw(msg.sender, _pid, _amount);
    }

    function emergencyWithdraw() public onlyController {
        ranbased.transfer(controller, ranbased.balanceOf(address(this)));
    }  
    function setStartBlock(uint _startBlock) external onlyController {
        require(startBlock == 0 && _startBlock > 0, " startBlock > 0 ?");
        startBlock = _startBlock;
    }
}

