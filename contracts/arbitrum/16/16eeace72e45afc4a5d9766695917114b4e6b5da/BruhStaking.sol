//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";

contract BruhStaking is Ownable, ReentrancyGuard {
    struct SharedData {
        uint256 totalAmount;
        uint256 rewardPerShareToken;
        uint256 rewardRemain;
        uint256 rewardDeposited;
    }

    struct Reward {
        uint256 totalExcludedToken;
        uint256 lastClaim;
    }

    struct UserData {
        uint256 amount;
        uint256 lockedTime;
    }

    IERC20 public immutable rewardToken;

    SharedData public sharedData;

    uint256 public constant ACC_FACTOR = 10 ** 18;

    uint256 public minStakingAmount = 1_000 * 1e6;
    uint256 public totalTokenClaimed;
    uint256 public rewardPerSecond;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public lastDistribution;
    uint256 public totalUsers;

    uint256 public totalDistributed;

    bool public isFinished;
    bool public isEmergency;

    mapping(address => UserData) public userData;
    mapping(address => Reward) private rewards;

    event NewLock(address user, uint256 amount);
    event RewardDeposited(uint256 amount, uint256 time);
    event StakingCreated(uint256 totalAmount, uint256 startTime, uint256 endTime);
    event ClaimRewards(address indexed recipient, uint256 tokenAmount);
    event Unlock(address indexed user, uint256 amount);
    event SettingsUpdated(uint256 oldMinStakingAmount, uint256 newMinStakingAmount);
    event EmergencyEnabled(bool emergency, uint256 time);
    event EmergencyUnlock(address indexed user, uint256 amount);

    constructor(address _rewardToken) {
        rewardToken = IERC20(_rewardToken);
    }

    function start(
        uint256 _rewardAmount,
        uint256 _startTime
    ) external onlyOwner nonReentrant {
        require(startTime == 0, "already created");
        require(
            _startTime >= block.timestamp,
             "wrong time"
        );
        require(_rewardAmount > 0, 'zero amount passed');
        require(rewardToken.transferFrom(msg.sender, address(this), _rewardAmount), "Token transfer failed");

        endTime = _startTime + 90 days;
        uint256 totalStakingTimeInSeconds = endTime - _startTime;
        rewardPerSecond = _rewardAmount / totalStakingTimeInSeconds;
        startTime = _startTime;
        lastDistribution = startTime;
        sharedData.rewardRemain += _rewardAmount;
        sharedData.rewardDeposited += _rewardAmount;
        emit StakingCreated(_rewardAmount, startTime, endTime);
    }

    function participate(uint256 amount) external nonReentrant {
        require(block.timestamp < endTime, "staking ended");

        require(
            rewardToken.transferFrom(_msgSender(), address(this), amount),
            "token transfer failed"
        );

        _autoRewardDistribution();

        if (getUnpaid(msg.sender) > 0) {
            _claim(_msgSender());
        }

        uint256 storedAmount = userData[_msgSender()].amount;
        uint256 totalAmount = userData[_msgSender()].amount + amount;
        require(totalAmount >= minStakingAmount, "input less than minimum");

        if (storedAmount == 0) {
            totalUsers++;
        }

        sharedData.totalAmount += totalAmount - storedAmount;

        userData[_msgSender()].amount = totalAmount;
        userData[_msgSender()].lockedTime = block.timestamp;

        rewards[_msgSender()].totalExcludedToken = getCumulativeRewards(userData[_msgSender()].amount);

        emit NewLock(_msgSender(), totalAmount);
    }

    function claim() external nonReentrant {
        _autoRewardDistribution();
        _claim(_msgSender());
    }

    function unlock() public nonReentrant {
        require(userData[_msgSender()].amount > 0, "Nothing to unlock");

        _autoRewardDistribution();

        //claim reward
        uint256 unclaimedAmountToken = getUnpaid(_msgSender());
        if (unclaimedAmountToken > 0) {
            _claim(_msgSender());
        }

        sharedData.totalAmount -= userData[_msgSender()].amount;

        require(
            rewardToken.transfer(_msgSender(), userData[_msgSender()].amount),
            "token transfer failed"
        );

        totalUsers--;

        emit Unlock(_msgSender(), userData[_msgSender()].amount);
        delete userData[_msgSender()];
    }

    function emergencyUnlock() external nonReentrant {
        require(isEmergency, "Emergency not enabled");
        require(userData[_msgSender()].amount > 0, "Nothing to unlock");

        sharedData.totalAmount -= userData[_msgSender()].amount;

        require(
            rewardToken.transfer(_msgSender(), userData[_msgSender()].amount),
            "token transfer failed"
        );
        totalUsers--;
        emit EmergencyUnlock(_msgSender(), userData[_msgSender()].amount);
        delete userData[_msgSender()];
    }

    function _distributeReward(uint256 amount) internal {
        if (sharedData.totalAmount > 0) {
            sharedData.rewardPerShareToken += (amount * ACC_FACTOR) / sharedData.totalAmount;
            lastDistribution = block.timestamp;
            emit RewardDeposited(amount, block.timestamp);
        }
    }

    function getCumulativeRewards(
        uint256 share
    ) internal view returns (uint256) {
        return share * sharedData.rewardPerShareToken / ACC_FACTOR;
    }

    function getUnpaid(
        address shareholder
    ) internal view returns (uint256) {
        if (userData[shareholder].amount == 0) {
            return (0);
        }

        uint256 earnedRewardsToken = getCumulativeRewards(userData[shareholder].amount);
        uint256 rewardsExcludedToken = rewards[shareholder].totalExcludedToken;
        if (
            earnedRewardsToken <= rewardsExcludedToken
        ) {
            return (0);
        }

        return (
            earnedRewardsToken - rewardsExcludedToken
        );
    }

    function viewUnpaid(address user) external view returns (uint256) {
        if (userData[user].amount == 0) {
            return (0);
        }
        uint256 unpaidAmount = getUnpaid(user);
        uint256 time;
        if (block.timestamp >= endTime) {
            time = endTime;
        } else {
            time = block.timestamp;
        }
        if  (time > lastDistribution) {
            uint256 userRewardPerSecond = rewardPerSecond * userData[user].amount / sharedData.totalAmount;
            uint256 accumulatedRewards = userRewardPerSecond * (time - lastDistribution);
            unpaidAmount += accumulatedRewards;
        }
        return unpaidAmount;
    }

    function _autoRewardDistribution() internal {
        if (block.timestamp >= endTime && !isFinished){
            uint256 accumulatedRewards = (endTime - lastDistribution)*rewardPerSecond;
            totalDistributed += accumulatedRewards;
            _distributeReward(accumulatedRewards);
            lastDistribution = endTime;
            isFinished = true;
        } else {
            if  (block.timestamp > lastDistribution && !isFinished) {
                uint256 accumulatedRewards = (block.timestamp - lastDistribution)*rewardPerSecond;
                totalDistributed += accumulatedRewards;
                _distributeReward(accumulatedRewards);
            }
        }
    }

    function _claim(address user) internal {
        require(
            block.timestamp > rewards[user].lastClaim,
            "can only claim once per block"
        );
        require(userData[user].amount > 0, "no tokens staked");

        uint256 amountToken = getUnpaid(user);
        require(amountToken > 0, "nothing to claim");

        totalTokenClaimed += amountToken;
        rewards[user].totalExcludedToken = getCumulativeRewards(
            userData[user].amount
        );

        if (!isEmergency) {
           require(sharedData.rewardRemain - amountToken >= 0, "reward pool is empty");
            sharedData.rewardRemain -= amountToken;
        }

        require(rewardToken.transfer(user, amountToken), "token transfer failed");

        rewards[user].lastClaim = block.timestamp;
        emit ClaimRewards(user, amountToken);
    }

    function changeMinStakingAmount(
        uint256 _newMinStakingAmount
    ) external onlyOwner {
        uint256 oldMinStakingAmount = minStakingAmount;
        minStakingAmount = _newMinStakingAmount;
        emit SettingsUpdated(oldMinStakingAmount, minStakingAmount);
    }

    function enableEmergency() external onlyOwner {
        require(!isEmergency, "emergency already enabled");

        endTime = block.timestamp;
        _autoRewardDistribution();
        isEmergency = true;
        sharedData.rewardRemain = sharedData.rewardDeposited - totalDistributed;

        emit EmergencyEnabled(true, block.timestamp);
    }

    function withdraw(address _token, uint256 _amount) external onlyOwner {
        if (_token != address(0)) {
            if (_token == address(rewardToken)) {
                require(isEmergency, "Emergency not enabled");
                require(_amount <= sharedData.rewardRemain, "amount exceeded remain reward pool");
                sharedData.rewardRemain -= _amount;
            }
			IERC20(_token).transfer(msg.sender, _amount);
		} else {
			(bool success, ) = payable(msg.sender).call{ value: _amount }("");
			require(success, "Can't send ETH");
		}
	}

    receive() external payable {}
}
