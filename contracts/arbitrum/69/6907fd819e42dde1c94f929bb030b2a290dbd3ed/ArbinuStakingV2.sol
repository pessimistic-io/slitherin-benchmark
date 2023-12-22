// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";

interface IArbinuLPStaking {
    function getTotalDistributedReward() external view returns (uint256 _value);
}

contract ArbinuStakingV2 is Initializable, OwnableUpgradeable {
    address payable public distributor;

    IERC20 public arbinuToken;
    IArbinuLPStaking public arbinuLpStaking;

    uint256 public totalStaked;
    uint256 public totalDistributedReward;
    uint256 public totalWithdrawn;
    uint256 public uniqueStakers;
    uint256 public currentStakedAmount;
    uint256 public migratedAmount;
    uint256 public duration;
    uint256 public minDeposit;
    uint256 public percentDivider;

    struct PoolData {
        uint256 poolDuration;
        uint256 rewardPercentage;
        uint256 totalStakers;
        uint256 totalStaked;
        uint256 poolCurrentStaked;
        uint256 totalDistributedReward;
        uint256 totalWithdrawn;
    }

    struct StakeData {
        uint256 planIndex;
        uint256 amount;
        uint256 reward;
        uint256 startTime;
        uint256 capturedFee;
        uint256 currentStaked;
        uint256 endTime;
        uint256 harvestTime;
        bool isWithdrawn;
    }

    struct UserData {
        bool isExists;
        uint256 stakeCount;
        uint256 totalStaked;
        uint256 totalWithdrawn;
        uint256 totalDistributedReward;
        mapping(uint256 => StakeData) stakeRecord;
    }

    mapping(address => UserData) internal users;
    mapping(uint256 => PoolData) public pools;

    uint256 public excludedAmount;

    event STAKE(address staker, uint256 amount);
    event WITHDRAW(address staker, uint256 amount);

    function initialize(
        address payable _distributorAddress,
        address payable _arbinuTokenAddress,
        address payable _arbinuLpStakingAddress
    ) public initializer {
        __Ownable_init();
        arbinuToken = IERC20(_arbinuTokenAddress);
        arbinuLpStaking = IArbinuLPStaking(_arbinuLpStakingAddress);
        distributor = _distributorAddress;
        minDeposit = 100e18;
        percentDivider = 10000;
        duration = 1 days;
    }

    function getCapturedFee() public view returns (uint256 _value) {
        _value =
            (getDistributorBalance() +
                arbinuLpStaking.getTotalDistributedReward() +
                migratedAmount +
                totalDistributedReward -
                excludedAmount) -
            currentStakedAmount;
    }

    function stake(uint256 _amount, uint256 _planIndex) public {
        require(_planIndex < 2, "Invalid index");
        require(_amount >= minDeposit, "stake more than min amount");

        UserData storage user = users[msg.sender];
        StakeData storage userStake = user.stakeRecord[user.stakeCount];
        PoolData storage poolInfo = pools[_planIndex];

        if (!users[msg.sender].isExists) {
            users[msg.sender].isExists = true;
            uniqueStakers++;
        }

        arbinuToken.transferFrom(msg.sender, distributor, _amount);

        userStake.amount = _amount;
        userStake.planIndex = _planIndex;
        userStake.startTime = block.timestamp;
        userStake.currentStaked = poolInfo.totalStakers;
        userStake.endTime = block.timestamp + poolInfo.poolDuration;
        user.stakeCount++;
        user.totalStaked += _amount;
        poolInfo.totalStaked += _amount;
        poolInfo.poolCurrentStaked += _amount;
        userStake.capturedFee = getCapturedFee();
        poolInfo.totalStakers++;

        totalStaked += _amount;
        currentStakedAmount += _amount;

        emit STAKE(msg.sender, _amount);
    }

    function withdraw(uint256 _index) public {
        UserData storage user = users[msg.sender];
        StakeData storage userStake = user.stakeRecord[_index];
        PoolData storage poolInfo = pools[userStake.planIndex];

        require(_index < user.stakeCount, "Invalid index");
        require(!userStake.isWithdrawn, "Already withdrawn");
        require(block.timestamp > userStake.endTime, "Wait for end time");

        (userStake.reward, , ) = calculateReward(
            msg.sender,
            _index,
            userStake.planIndex
        );
        arbinuToken.transferFrom(
            distributor,
            msg.sender,
            userStake.amount + userStake.reward
        );

        userStake.isWithdrawn = true;
        user.totalDistributedReward += userStake.reward;
        poolInfo.totalDistributedReward += userStake.reward;
        user.totalWithdrawn += userStake.amount;
        poolInfo.totalWithdrawn += userStake.amount;
        poolInfo.poolCurrentStaked -= userStake.amount;

        totalDistributedReward += userStake.reward;
        totalWithdrawn += userStake.amount;
        currentStakedAmount -= userStake.amount;

        emit WITHDRAW(msg.sender, userStake.amount);
        emit WITHDRAW(msg.sender, userStake.reward);
    }

    function harvest(uint256 _index) public {
        UserData storage user = users[msg.sender];
        StakeData storage userStake = user.stakeRecord[_index];
        PoolData storage poolInfo = pools[userStake.planIndex];

        require(
            block.timestamp > userStake.harvestTime + duration,
            "Wait for duration to harvest"
        );
        require(_index < user.stakeCount, "Invalid index");
        require(!userStake.isWithdrawn, "Already withdrawn");
        require(block.timestamp > userStake.endTime, "Wait for end time");

        (userStake.reward, , ) = calculateReward(
            msg.sender,
            _index,
            userStake.planIndex
        );
        arbinuToken.transferFrom(distributor, msg.sender, userStake.reward);

        user.totalDistributedReward += userStake.reward;
        poolInfo.totalDistributedReward += userStake.reward;
        totalDistributedReward += userStake.reward;
        userStake.capturedFee = getCapturedFee();
        userStake.harvestTime = block.timestamp;

        emit WITHDRAW(msg.sender, userStake.reward);
    }

    function calculateReward(
        address _userAdress,
        uint256 _index,
        uint256 _planIndex
    )
        public
        view
        returns (uint256 _reward, uint256 rewardPool, uint256 totalFee)
    {
        PoolData storage poolInfo = pools[_planIndex];
        UserData storage user = users[_userAdress];
        StakeData storage userStake = user.stakeRecord[_index];

        uint256 userShare = (userStake.amount * percentDivider) /
            poolInfo.poolCurrentStaked;
        totalFee = getCapturedFee() - userStake.capturedFee;
        rewardPool = (totalFee * poolInfo.rewardPercentage) / percentDivider;

        _reward = (rewardPool * userShare) / percentDivider;
    }

    function getUserInfo(
        address _user
    )
        public
        view
        returns (
            bool _isExists,
            uint256 _stakeCount,
            uint256 _totalStaked,
            uint256 _totalDistributedReward,
            uint256 _totalWithdrawn
        )
    {
        UserData storage user = users[_user];

        _isExists = user.isExists;
        _stakeCount = user.stakeCount;
        _totalStaked = user.totalStaked;
        _totalDistributedReward = user.totalDistributedReward;
        _totalWithdrawn = user.totalWithdrawn;
    }

    function getUserStakeInfo(
        address _user,
        uint256 _index
    )
        public
        view
        returns (
            uint256 _planIndex,
            uint256 _Amount,
            uint256 _capturedFee,
            uint256 _startTime,
            uint256 _endTime,
            uint256 _reward,
            uint256 _harvestTime,
            bool _isWithdrawn
        )
    {
        StakeData storage userStake = users[_user].stakeRecord[_index];

        _planIndex = userStake.planIndex;
        _Amount = userStake.amount;
        _capturedFee = userStake.capturedFee;
        _startTime = userStake.startTime;
        _endTime = userStake.endTime;
        _reward = userStake.reward;
        _harvestTime = userStake.harvestTime;
        _isWithdrawn = userStake.isWithdrawn;
    }

    function getDistributorBalance() public view returns (uint256 _balance) {
        _balance = arbinuToken.balanceOf(distributor);
    }

    function adm_setMigratedFundsForRewardsPool(
        uint256 _amount
    ) public onlyOwner {
        migratedAmount = _amount;
    }

    function adm_addMigratedFundsForRewardsPool(
        uint256 _addedAmount
    ) public onlyOwner {
        migratedAmount += _addedAmount;
    }

    function adm_setExcludedFundsForRewardsPool(
        uint256 _amount
    ) public onlyOwner {
        excludedAmount = _amount;
    }

    function adm_addExcludedFundsForRewardsPool(
        uint256 _addedAmount
    ) public onlyOwner {
        excludedAmount += _addedAmount;
    }

    function adm_setLpStakingInstance(address _address) public onlyOwner {
        arbinuLpStaking = IArbinuLPStaking(_address);
    }

    function adm_setDuration(uint256 _duration) public onlyOwner {
        duration = _duration;
    }

    function adm_setDistributor(
        address payable _distributorAddress
    ) external onlyOwner {
        distributor = _distributorAddress;
    }

    function adm_setMinAmount(uint256 _amount) external onlyOwner {
        minDeposit = _amount;
    }

    function adm_setPoolsDuration(uint256 _1, uint256 _2) external onlyOwner {
        pools[0].poolDuration = _1;
        pools[1].poolDuration = _2;
    }

    function adm_setPoolsRewardPercentage(
        uint256 _1,
        uint256 _2
    ) external onlyOwner {
        pools[0].rewardPercentage = _1;
        pools[1].rewardPercentage = _2;
    }
}

