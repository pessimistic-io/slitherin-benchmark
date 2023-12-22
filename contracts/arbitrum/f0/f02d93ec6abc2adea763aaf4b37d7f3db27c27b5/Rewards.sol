// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./IERC1155Upgradeable.sol";
import "./ERC1155Holder.sol";
import "./RewardsStorage.sol";
import "./AccessControl.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./BlockNonEOAUpgradeable.sol";
import "./Initializable.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Math.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./OwnableUpgradeable.sol";
import "./AddressArray.sol";
import "./IWETH.sol";
import "./IAddressProvider.sol";
import "./IRewards.sol";
import "./ILendVault.sol";
import "./RewardsStorage.sol";

contract Rewards is
    AccessControl,
    IRewards,
    RewardsStorage,
    BlockNonEOAUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC1155Holder
{
    using SafeERC20 for IERC20;
    using AddressArray for address[];
    using Address for address;
    using SafeMath for uint256;

    /**
     * @notice Initializes the upgradeable contract with the provided parameters
     */
    function initialize(
        address _addressProvider,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _endBlock
    ) external initializer {
        __BlockNonEOAUpgradeable_init(_addressProvider);
        __AccessControl_init(_addressProvider);
        __ReentrancyGuard_init();

        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;
        callerWhitelistActive = true;
        withdrawEnabled = false;
    }

    modifier isCallerWhitelisted() {
        address _caller = msg.sender;
        if (callerWhitelistActive) {
            require(callerWhitelist[_caller], "Not Authorized");
        }
        _;
    }

    modifier isWithdrawEnabled() {
        require(withdrawEnabled == true, "Withdraw not enabled yet");
        _;
    }

    /// @inheritdoc IRewards
    function setCallerWhitelist(
        address _callerToWhitelist,
        bool _setOrUnset
    ) external restrictAccess(GOVERNOR) {
        require(_callerToWhitelist != address(0), "No address set");
        callerWhitelist[_callerToWhitelist] = _setOrUnset;
    }

    /// @inheritdoc IRewards
    function changeRewardsPerBlock(
        uint256 _rewardPerBlock        
    ) external restrictAccess(GOVERNOR) {
        require( _rewardPerBlock > 0, "Has to be greater than 0");
       rewardPerBlock = _rewardPerBlock;
    }    

    /// @inheritdoc IRewards
    function setParameters(
        bool _callerWhitelistActive,
        bool _withdrawEnabled
    ) external restrictAccess(GOVERNOR) {
        callerWhitelistActive = _callerWhitelistActive;
        withdrawEnabled = _withdrawEnabled;
    }

    /// @inheritdoc IRewards
    function setEndblock(uint256 _endBlock) external restrictAccess(GOVERNOR) {
        endBlock = _endBlock;
    }

    /// @inheritdoc IRewards
    function poolLength() external view returns (uint256) {
        return pools.length;
    }

    /// @inheritdoc IRewards
    function balanceOf(
        address _poolAddress,
        address _user,
        bool _isLending,
        address _lendingToken
    ) external view returns (uint256 stakedBalance) {
        (uint256 _pid, ) = getPoolId(_poolAddress, _isLending, _lendingToken);
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }

    /// @inheritdoc IRewards
    function getPendingHarvestableRewards(
        address _poolAddress,
        address _user,
        bool _isLending,
        address _lendingToken
    ) external view returns (int256 harvestBalance) {
        (uint256 _pid, ) = getPoolId(_poolAddress, _isLending, _lendingToken);
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accumulatedReward = user.pendingRewards;
        int256 _pendingReward = int256(accumulatedReward) - int256(user.rewardDebt);
        return _pendingReward;
    }

    /// @inheritdoc IRewards
    function getPoolId(
        address _poolAddress,
        bool _isLending,
        address _lendingToken
    ) public view virtual returns (uint256 poolId, bool exists) {
        if (!_isLending) {
            for (uint i = 0; i < pools.length; i++) {
                if (pools[i].stakingToken == _poolAddress) {
                    return (i, true);
                }
            }
        } else {
            for (uint i = 0; i < pools.length; i++) {
                if (
                    pools[i].stakingToken == _poolAddress &&
                    pools[i].lendingToken == _lendingToken
                ) {
                    return (i, true);
                }
            }
        }
        return (2**256 - 1, false);
    }

    /// @inheritdoc IRewards
    function getPoolData(
        address _poolAddress,
        bool _isLending,
        address _lendingToken
    ) public view virtual returns (Pool memory pool) {
        (uint256 poolId, bool exists) = getPoolId(_poolAddress, _isLending, _lendingToken);
        require(exists, 'No pool data');
        return pools[poolId];
    }    

    /// @inheritdoc IRewards
    function addPool(
        address _stakingToken,
        address _rewardToken,
        uint256 _allocationPoints,
        bool _isLending,
        address _lendingToken
    ) external restrictAccess(GOVERNOR) {
        //add for lending and strategy/vault
        pools.push(
            Pool({
                stakingToken: _stakingToken,
                rewardToken: _rewardToken,
                allocationPoints: _allocationPoints,
                lastRewardBlock: block.number > startBlock
                    ? block.number
                    : startBlock,
                accRewardPerShare: 0,
                isLending: _isLending,
                lendingToken: _lendingToken
            })
        );
        totalAllocationPoints[_rewardToken] += _allocationPoints;
    }

    /// @inheritdoc IRewards
    function setPool(
        uint256 _pid,
        uint256 _allocationPoints
    ) external restrictAccess(GOVERNOR) {
        require(_pid < pools.length, "Invalid pool ID");
        Pool storage pool = pools[_pid];
        totalAllocationPoints[pool.rewardToken] -= pool.allocationPoints;
        totalAllocationPoints[pool.rewardToken] += _allocationPoints;
        pool.allocationPoints = _allocationPoints;
    }

    /// @inheritdoc IRewards
    function getPendingReward(
        uint256 _pid,
        address _user
    ) public view returns (uint256 rewards) {
        Pool storage pool = pools[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 totalStakedAmount = 0;
        if (pool.isLending) {
            totalStakedAmount = ILendVault(pool.stakingToken).balanceOf(
                address(this),
                pool.lendingToken
            );
        } else {
            totalStakedAmount = IERC20(pool.stakingToken).balanceOf(
                address(this)
            );
        }
        uint256 stakedAmount = user.amount;
        if (
            block.number > pool.lastRewardBlock &&
            stakedAmount != 0 &&
            totalStakedAmount > 0
        ) {
            uint256 blockToCalculate = endBlock > block.number
                ? block.number
                : endBlock;
            uint256 blocksSinceLastUpdate = blockToCalculate -
                pool.lastRewardBlock;
            uint256 rewardAmount = (blocksSinceLastUpdate *
                rewardPerBlock *
                pool.allocationPoints) /
                totalAllocationPoints[pool.rewardToken];
            accRewardPerShare += (rewardAmount * PRECISION) / totalStakedAmount;
        }
        uint256 stakedShare = user
            .amount
            .mul(accRewardPerShare)
            .div(PRECISION)
            .sub(user.rewardDebt);
        return stakedShare;
    }

    /// @inheritdoc IRewards
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _depositor
    ) external nonReentrant isCallerWhitelisted {
        require(block.number >= startBlock, "Distribution has not started yet");
        require(block.number <= endBlock, "Distribution has ended");
        require(_pid < pools.length, "Invalid pool ID");
        _deposit(_pid, _amount, _depositor);
    }

    /// @inheritdoc IRewards
    function deposit(
        address _poolAddress,
        uint256 _amount,
        address _depositor,
        bool _isLending,
        address _lendingToken
    ) external nonReentrant isCallerWhitelisted {
        require(block.number >= startBlock, "Distribution has not started yet");
        require(block.number <= endBlock, "Distribution has ended");
        (uint256 _pid, ) = getPoolId(_poolAddress, _isLending, _lendingToken);                
        require(_pid < pools.length, "Invalid pool ID");        
        _deposit(_pid, _amount, _depositor);
    }

    /// @inheritdoc IRewards
    function massUpdatePools(
        uint256[] calldata pids
    ) external nonReentrant restrictAccess(GOVERNOR) {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }

    /// @inheritdoc IRewards
    function withdraw(
        address _poolAddress,
        uint256 _amount,
        address _depositor,
        bool _isLending,
        address _lendingToken
    ) external nonReentrant isCallerWhitelisted {
        (uint256 _pid, ) = getPoolId(_poolAddress, _isLending, _lendingToken);
        updatePool(_pid);
        require(_pid < pools.length, "Invalid pool ID");
        Pool storage pool = pools[_pid];
        UserInfo storage user = userInfo[_pid][_depositor];
        require(user.amount >= _amount, "Insufficient staked amount");
        user.pendingRewards = user.amount.mul(pool.accRewardPerShare).div(
            PRECISION
        ); //.sub(user.rewardDebt);
        if (_amount > 0) {
            user.amount -= _amount;
            if (pool.isLending) {
                IERC1155Upgradeable(pool.stakingToken).safeTransferFrom(
                    address(this),
                    address(_depositor),
                    uint(keccak256(abi.encodePacked(pool.lendingToken))),
                    _amount,
                    ""
                );
            } else {
                IERC20(pool.stakingToken).transfer(
                    address(_depositor),
                    _amount
                );
            }
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(
            PRECISION
        );
        emit Withdraw(msg.sender, _pid, _amount);
    }

    /// @inheritdoc IRewards
    function harvest(
        address _poolAddress,
        bool _isLending,
        address _lendingToken
    ) public nonReentrant isWithdrawEnabled onlyEOA {
        (uint256 _pid, ) = getPoolId(_poolAddress, _isLending, _lendingToken);
        updatePool(_pid);
        Pool storage pool = pools[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 accumulatedReward = user.pendingRewards;
        uint256 _pendingReward = accumulatedReward.sub(user.rewardDebt);
        if (_pendingReward == 0) {
            return;
        }
        // Effects
        user.rewardPaid += _pendingReward;
        user.pendingRewards = 0;
        // Interactions
        safeRewardTransfer(pool.rewardToken, msg.sender, _pendingReward);
        emit Harvest(msg.sender, _pid, _pendingReward);
    }

    /// @inheritdoc IRewards
    function emergencyWithdraw(
        uint256 _pid
    ) external onlyEOA nonReentrant isWithdrawEnabled {
        require(_pid < pools.length, "Invalid pool ID");
        Pool storage pool = pools[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        require(amount > 0, "No staked amount");
        user.amount = 0;
        user.rewardPaid = 0;
        if (pool.isLending) {
            IERC1155Upgradeable(pool.stakingToken).safeTransferFrom(
                address(this),
                address(msg.sender),
                uint(keccak256(abi.encodePacked(pool.lendingToken))),
                amount,
                ""
            );
        } else {
            IERC20(pool.stakingToken).transfer(address(msg.sender), amount);
        }
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    /// @inheritdoc IRewards
    function withdrawAllLeftoverRewards(
        uint256 _amount,
        address _rewardToken
    ) external restrictAccess(GOVERNOR) {
        safeRewardTransfer(_rewardToken, provider.governance(), _amount);
    }

    // ---------- Internal Helper Functions ----------

    function _deposit(
        uint256 _pid,
        uint256 _amount,
        address _depositor
    ) internal {
        Pool storage pool = pools[_pid];
        if (pool.isLending) {
            IERC1155Upgradeable(pool.stakingToken).safeTransferFrom(
                _depositor,
                address(this),
                uint(keccak256(abi.encodePacked(pool.lendingToken))),
                _amount,
                ""
            );
        } else {
            IERC20(pool.stakingToken).transferFrom(
                _depositor,
                address(this),
                _amount
            );
        }
        updatePool(_pid);
        UserInfo storage user = userInfo[_pid][_depositor];
        if (user.amount > 0) {
            user.pendingRewards += user
                .amount
                .mul(pool.accRewardPerShare)
                .div(PRECISION)
                .sub(user.rewardDebt);
        }
        if (_amount > 0) {
            user.amount += _amount;
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(
            PRECISION
        );
        emit Deposit(_depositor, _pid, _amount);
    }

    function updatePool(uint256 _pid) internal {
        Pool storage pool = pools[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 stakedTokenSupply = 0;
        if (pool.isLending) {
            stakedTokenSupply = IERC1155Upgradeable(pool.stakingToken)
                .balanceOf(
                    address(this),
                    uint(keccak256(abi.encodePacked(pool.lendingToken)))
                );
        } else {
            stakedTokenSupply = IERC20(pool.stakingToken).balanceOf(
                address(this)
            );
        }
        if (stakedTokenSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 blockToCalculate = endBlock > block.number
            ? block.number
            : endBlock;
        uint256 blocksSinceLastUpdate = blockToCalculate - pool.lastRewardBlock;
        uint256 rewardAmount = (blocksSinceLastUpdate *
            rewardPerBlock *
            pool.allocationPoints) / totalAllocationPoints[pool.rewardToken];
        pool.accRewardPerShare +=
            (rewardAmount * PRECISION) /
            stakedTokenSupply;
        pool.lastRewardBlock = endBlock > block.number
            ? block.number
            : endBlock;
    }

    function safeRewardTransfer(
        address _rewardToken,
        address _to,
        uint256 _amount
    ) internal {
        uint256 rewardTokenBalance = IERC20(_rewardToken).balanceOf(
            address(this)
        );
        if (_amount > rewardTokenBalance) {
            IERC20(_rewardToken).transfer(_to, rewardTokenBalance);
        } else {
            IERC20(_rewardToken).transfer(_to, _amount);
        }
    }
}

