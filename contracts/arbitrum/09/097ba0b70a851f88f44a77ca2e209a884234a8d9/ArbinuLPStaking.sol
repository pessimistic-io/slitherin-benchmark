// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import "./IUniswapV2Pair.sol";

interface IArbinuStaking {
    function getCapturedFee() external view returns (uint256 _value);
}

contract ArbinuLPStaking is Initializable, OwnableUpgradeable {
    address payable public distributor;

    IUniswapV2Pair public arbinuLpPair;
    IERC20 public arbinuToken;
    IArbinuStaking public arbinuStaking;

    uint256 public totalStaked;
    uint256 public totalDistributedReward;
    uint256 public totalWithdrawn;
    uint256 public uniqueStakers;
    uint256 public currentStakedAmount;
    uint256 public feePrecentage;
    uint256 public duration;
    uint256 public minDeposit;
    uint256 public percentDivider;

    struct StakeData {
        uint256 planIndex;
        uint256 lpAmount;
        uint256 reward;
        uint256 startTime;
        uint256 Capturefee;
        uint256 CurrentStaked;
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

    event STAKE(address staker, uint256 amount);
    event WITHDRAW(address staker, uint256 amount);

    function initialize(
        address payable _distributorAddress,
        address payable _arbinuTokenAddress,
        address payable _lpPairAddress
    ) public initializer {
        __Ownable_init();
        distributor = _distributorAddress;
        arbinuToken = IERC20(_arbinuTokenAddress);
        arbinuLpPair = IUniswapV2Pair(_lpPairAddress);
        arbinuStaking = IArbinuStaking(
            0x0000000000000000000000000000000000000000
        );
        duration = 1 days;
        minDeposit = 100;
        percentDivider = 10000;
    }

    function stake(uint256 _amount) public {
        require(_amount >= minDeposit, "Stake more than min amount");
        UserData storage user = users[msg.sender];
        StakeData storage userStake = user.stakeRecord[user.stakeCount];
        if (!users[msg.sender].isExists) {
            users[msg.sender].isExists = true;
            uniqueStakers++;
        }

        arbinuLpPair.transferFrom(msg.sender, address(this), _amount);

        userStake.lpAmount = _amount;
        userStake.startTime = block.timestamp;
        userStake.Capturefee = arbinuStaking.getCapturedFee();
        user.stakeCount++;
        user.totalStaked += _amount;

        totalStaked += _amount;
        currentStakedAmount += _amount;

        emit STAKE(msg.sender, _amount);
    }

    function withdraw(uint256 _index) public {
        UserData storage user = users[msg.sender];
        StakeData storage userStake = user.stakeRecord[_index];

        require(_index < user.stakeCount, "Invalid index");
        require(!userStake.isWithdrawn, "Already withdrawn");

        arbinuLpPair.transfer(msg.sender, userStake.lpAmount);

        userStake.reward = calculateReward(msg.sender, _index);
        if (userStake.reward > 0) {
            arbinuToken.transferFrom(distributor, msg.sender, userStake.reward);
        }

        userStake.isWithdrawn = true;
        user.totalDistributedReward += userStake.reward;
        totalDistributedReward += userStake.reward;
        user.totalWithdrawn += userStake.lpAmount;
        userStake.endTime = block.timestamp;

        totalWithdrawn += userStake.lpAmount;
        currentStakedAmount -= userStake.lpAmount;

        emit WITHDRAW(msg.sender, userStake.lpAmount);
        emit WITHDRAW(msg.sender, userStake.reward);
    }

    function calculateReward(
        address _userAdress,
        uint256 _index
    ) public view returns (uint256 _reward) {
        UserData storage user = users[_userAdress];
        StakeData storage userStake = user.stakeRecord[_index];

        uint256 userShare = (userStake.lpAmount * percentDivider) /
            currentStakedAmount;
        uint256 totalFee = arbinuStaking.getCapturedFee() -
            userStake.Capturefee;
        uint256 rewardPool = (totalFee * feePrecentage) / percentDivider;

        _reward = (rewardPool * userShare) / percentDivider;
    }

    function harvest(uint256 _index) public {
        UserData storage user = users[msg.sender];
        StakeData storage userStake = user.stakeRecord[_index];

        require(
            block.timestamp > userStake.harvestTime + duration,
            "Wait for duration to harvest"
        );
        require(_index < user.stakeCount, "Invalid index");
        require(!userStake.isWithdrawn, "Amount withdrawn");

        userStake.reward = calculateReward(msg.sender, _index);
        arbinuToken.transferFrom(distributor, msg.sender, userStake.reward);

        user.totalDistributedReward += userStake.reward;
        userStake.Capturefee = arbinuStaking.getCapturedFee();
        userStake.harvestTime = block.timestamp;

        totalDistributedReward += userStake.reward;
    }

    function getTotalDistributedReward() public view returns (uint256 _value) {
        _value = totalDistributedReward;
    }

    function getCapturedFee() public view returns (uint256 fee) {
        fee = arbinuStaking.getCapturedFee();
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
            uint256 _lpAmount,
            uint256 _capturedFee,
            uint256 _startTime,
            uint256 _endTime,
            uint256 _reward,
            uint256 _harvestTime,
            bool _isWithdrawn
        )
    {
        StakeData storage userStake = users[_user].stakeRecord[_index];

        _lpAmount = userStake.lpAmount;
        _capturedFee = userStake.Capturefee;
        _startTime = userStake.startTime;
        _endTime = userStake.endTime;
        _reward = userStake.reward;
        _isWithdrawn = userStake.isWithdrawn;
        _harvestTime = userStake.harvestTime;
    }

    function adm_setDuration(uint256 _duration) public onlyOwner {
        duration = _duration;
    }

    function adm_setFeePercentage(uint256 _feePercentage) public onlyOwner {
        feePrecentage = _feePercentage;
    }

    function adm_setDistributor(
        address payable _distributor
    ) external onlyOwner {
        distributor = _distributor;
    }

    function adm_setTokenStakingInstance(address _address) public onlyOwner {
        arbinuStaking = IArbinuStaking(_address);
    }

    function adm_setMinAmount(uint256 _amount) external onlyOwner {
        minDeposit = _amount;
    }
}

