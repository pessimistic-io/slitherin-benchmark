// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IMultiRewardsBasePool.sol";
import "./TokenSaver.sol";

contract MultiRewardsLiquidityMiningManagerV3 is TokenSaver {
    using SafeERC20 for IERC20;

    bytes32 public constant GOV_ROLE = keccak256("GOV_ROLE");
    bytes32 public constant REWARD_DISTRIBUTOR_ROLE = keccak256("REWARD_DISTRIBUTOR_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    uint256 public MAX_POOL_COUNT = 10;

    IERC20 public immutable reward;
    address public rewardSource;
    uint256 public rewardPerSecond; //total reward amount per second
    uint256 public lastDistribution; //when rewards were last pushed
    uint256 public totalWeight;

    uint256 public distributorIncentive; //incentive to distributor
    uint256 public platformFee; //possible fee to build treasury
    uint256 public constant FEE_DENOMINATOR = 10000;
    address public treasury;

    mapping(address => bool) public poolAdded;
    Pool[] public pools;

    struct Pool {
        IMultiRewardsBasePool poolContract;
        uint256 weight;
    }

    modifier onlyGov() {
        require(hasRole(GOV_ROLE, _msgSender()), "MultiRewardsLiquidityMiningManagerV3.onlyGov: permission denied");
        _;
    }

    modifier onlyRewardDistributor() {
        require(
            hasRole(REWARD_DISTRIBUTOR_ROLE, _msgSender()),
            "MultiRewardsLiquidityMiningManagerV3.onlyRewardDistributor: permission denied"
        );
        _;
    }

    modifier onlyFeeManager() {
        require(
            hasRole(FEE_MANAGER_ROLE, _msgSender()),
            "MultiRewardsLiquidityMiningManagerV3.onlyFeeManager: permission denied"
        );
        _;
    }

    event PoolAdded(address indexed _pool, uint256 _weight);
    event PoolRemoved(uint256 indexed _poolId, address indexed _pool);
    event WeightAdjusted(uint256 indexed _poolId, address indexed _pool, uint256 _newWeight);
    event RewardsPerSecondSet(uint256 _rewardsPerSecond);
    event RewardsDistributed(address indexed _from, uint256 _amount);

    event RewardTokenSet(address _reward);
    event RewardSourceSet(address _rewardSource);
    event DistributorIncentiveSet(uint256 _distributorIncentive);
    event PlatformFeeSet(uint256 _platformFee);
    event TreasurySet(address _treasury);
    event DistributorIncentiveIssued(address indexed _to, uint256 _distributorIncentiveAmount);
    event PlatformFeeIssued(address indexed _to, uint256 _platformFeeAmount);

    constructor(
        address _reward,
        address _rewardSource,
        uint256 _distributorIncentive,
        uint256 _platformFee,
        address _treasury
    ) {
        require(_reward != address(0), "MultiRewardsLiquidityMiningManagerV3.constructor: reward token must be set");
        require(
            _rewardSource != address(0),
            "MultiRewardsLiquidityMiningManagerV3.constructor: rewardSource must be set"
        );
        require(
            _distributorIncentive <= FEE_DENOMINATOR,
            "MultiRewardsLiquidityMiningManagerV3.constructor: distributorIncentive cannot be greater than 100%"
        );
        require(
            _platformFee <= FEE_DENOMINATOR,
            "MultiRewardsLiquidityMiningManagerV3.constructor: platformFee cannot be greater than 100%"
        );
        if (_platformFee > 0) {
            require(_treasury != address(0), "MultiRewardsLiquidityMiningManagerV3.constructor: treasury must be set");
        }

        reward = IERC20(_reward);
        rewardSource = _rewardSource;
        distributorIncentive = _distributorIncentive;
        platformFee = _platformFee;
        treasury = _treasury;

        emit RewardTokenSet(_reward);
        emit RewardSourceSet(_rewardSource);
        emit DistributorIncentiveSet(_distributorIncentive);
        emit PlatformFeeSet(_platformFee);
        emit TreasurySet(_treasury);
    }

    function setFees(uint256 _distributorIncentive, uint256 _platformFee) external onlyFeeManager {
        require(
            _distributorIncentive <= FEE_DENOMINATOR,
            "MultiRewardsLiquidityMiningManagerV3.setFees: distributorIncentive cannot be greater than 100%"
        );
        require(
            _platformFee <= FEE_DENOMINATOR,
            "MultiRewardsLiquidityMiningManagerV3.setFees: platformFee cannot be greater than 100%"
        );
        distributorIncentive = _distributorIncentive;
        if (_platformFee > 0) {
            require(treasury != address(0), "MultiRewardsLiquidityMiningManagerV3.setFees: treasury must be set");
        }

        platformFee = _platformFee;

        emit DistributorIncentiveSet(_distributorIncentive);
        emit PlatformFeeSet(_platformFee);
    }

    function setTreasury(address _treasury) external onlyFeeManager {
        treasury = _treasury;

        emit TreasurySet(_treasury);
    }

    function addPool(address _poolContract, uint256 _weight) external onlyGov {
        distributeRewards();
        require(_poolContract != address(0), "MultiRewardsLiquidityMiningManagerV3.addPool: pool contract must be set");
        require(!poolAdded[_poolContract], "MultiRewardsLiquidityMiningManagerV3.addPool: Pool already added");
        require(
            pools.length < MAX_POOL_COUNT,
            "MultiRewardsLiquidityMiningManagerV3.addPool: Max amount of pools reached"
        );
        // add pool
        pools.push(Pool({ poolContract: IMultiRewardsBasePool(_poolContract), weight: _weight }));
        poolAdded[_poolContract] = true;

        // increase totalWeight
        totalWeight += _weight;

        // Approve max token amount
        reward.safeApprove(_poolContract, type(uint256).max);

        emit PoolAdded(_poolContract, _weight);
    }

    function removePool(uint256 _poolId) external onlyGov {
        distributeRewards();
        address poolAddress = address(pools[_poolId].poolContract);

        // decrease totalWeight
        totalWeight -= pools[_poolId].weight;

        // remove pool
        pools[_poolId] = pools[pools.length - 1];
        pools.pop();
        poolAdded[poolAddress] = false;

        // Approve 0 token amount
        reward.safeApprove(poolAddress, 0);

        emit PoolRemoved(_poolId, poolAddress);
    }

    function adjustWeight(uint256 _poolId, uint256 _newWeight) external onlyGov {
        distributeRewards();
        Pool storage pool = pools[_poolId];

        totalWeight -= pool.weight;
        totalWeight += _newWeight;

        pool.weight = _newWeight;

        emit WeightAdjusted(_poolId, address(pool.poolContract), _newWeight);
    }

    function setRewardPerSecond(uint256 _rewardPerSecond) external onlyGov {
        distributeRewards();
        rewardPerSecond = _rewardPerSecond;

        emit RewardsPerSecondSet(_rewardPerSecond);
    }

    function updateRewardSource(address _rewardSource) external onlyGov {
        require(
            _rewardSource != address(0),
            "MultiRewardsLiquidityMiningManagerV3.updateRewardSource: rewardSource address must be set"
        );
        distributeRewards();
        rewardSource = _rewardSource;
        emit RewardSourceSet(_rewardSource);
    }

    function distributeRewards() public onlyRewardDistributor {
        uint256 timePassed = block.timestamp - lastDistribution;
        uint256 totalRewardAmount = rewardPerSecond * timePassed;
        lastDistribution = block.timestamp;

        // return if pool length == 0
        if (pools.length == 0) {
            return;
        }

        // return if accrued rewards == 0
        if (totalRewardAmount == 0) {
            return;
        }

        uint256 platformFeeAmount = (totalRewardAmount * platformFee) / FEE_DENOMINATOR;
        uint256 distributorIncentiveAmount = (totalRewardAmount * distributorIncentive) / FEE_DENOMINATOR;

        reward.safeTransferFrom(
            rewardSource,
            address(this),
            totalRewardAmount + platformFeeAmount + distributorIncentiveAmount
        );

        for (uint256 i = 0; i < pools.length; i++) {
            Pool memory pool = pools[i];
            uint256 poolRewardAmount = (totalRewardAmount * pool.weight) / totalWeight;
            // Ignore tx failing to prevent a single pool from halting reward distribution
            address(pool.poolContract).call(
                abi.encodeWithSelector(pool.poolContract.distributeRewards.selector, address(reward), poolRewardAmount)
            );
        }

        if (treasury != address(0) && treasury != address(this) && platformFeeAmount > 0) {
            reward.safeTransfer(treasury, platformFeeAmount);
            emit PlatformFeeIssued(treasury, platformFeeAmount);
        }

        if (distributorIncentiveAmount > 0) {
            reward.safeTransfer(_msgSender(), distributorIncentiveAmount);
            emit DistributorIncentiveIssued(_msgSender(), distributorIncentiveAmount);
        }

        uint256 leftOverReward = reward.balanceOf(address(this));

        // send back excess but ignore dust
        if (leftOverReward > 1) {
            reward.safeTransfer(rewardSource, leftOverReward);
        }

        emit RewardsDistributed(_msgSender(), totalRewardAmount);
    }

    function getPools() external view returns (Pool[] memory result) {
        return pools;
    }
}

