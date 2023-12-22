// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./SafeERC20.sol";

contract Staking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Whether a limit is set for users
    bool public hasUserLimit;

    // Accrued token per share
    uint256 public accTokenPerShare;

    // The timestamp number when stake ends.
    uint256 public bonusEndTimeStamp;

    // The timestamp number when stake starts.
    uint256 public startTimeStamp;

    // The timestamp number of the last pool update
    uint256 public lastRewardTimeStamp;

    // The lock period of the stake amount
    uint256 public lockingDays;

    // The pool limit (0 if none)
    uint256 public poolLimitPerUser;

    // CAKE tokens created per time unit.
    uint256 public rewardPerTimeUnit;

    // The fee for early withdraw in percentage
    uint256 public withdrawFee;

    // The precision factor
    uint256 public PRECISION_FACTOR;

    // The total Reward Amount
    uint256 public stakedTokenSupply = 0;

    // The reward token
    IERC20 public rewardToken;

    // The staked token
    IERC20 public stakedToken;

    // The address of the fee recipient
    address public feeRecipient;

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => UserInfo) public userInfo;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
        uint256 lastDepositTimeStamp; // timestamp of last stake
    }

    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartAndEndTimeStamps(
        uint256 startTimeStamp,
        uint256 endTimeStamp
    );
    event NewRewardPerTimeUnit(uint256 rewardPerTimeUnit);
    event NewPoolLimit(uint256 poolLimitPerUser);
    event RewardsStop(uint256 timeStamp);
    event Withdraw(address indexed user, uint256 amount);
    event ClaimedRewards(address indexed user, uint256 amount);

    constructor(
        address _stakedTokenAddress,
        address _rewardTokenAddress,
        uint256 _rewardPerTimeUnit,
        uint256 _startTimeStamp,
        uint256 _bonusEndTimeStamp,
        uint256 _lockingDays,
        uint256 _poolLimitPerUser,
        uint256 _withdrawFee,
        address _feeRecipient
    ) {
        stakedToken = IERC20(_stakedTokenAddress);
        rewardToken = IERC20(_rewardTokenAddress);
        require(stakedToken.totalSupply() >= 0);
        require(rewardToken.totalSupply() >= 0);

        rewardPerTimeUnit = _rewardPerTimeUnit;
        // startTimeStamp = _startTimeStamp;
        startTimeStamp = block.timestamp;
        // bonusEndTimeStamp = _bonusEndTimeStamp;
        bonusEndTimeStamp = startTimeStamp + 4 * 365 days + 1 days;
        lockingDays = _lockingDays;
        withdrawFee = _withdrawFee;
        feeRecipient = _feeRecipient;

        if (_poolLimitPerUser > 0) {
            hasUserLimit = true;
            poolLimitPerUser = _poolLimitPerUser;
        }

        uint256 decimalsRewardToken = uint256(
            IERC20Metadata(_rewardTokenAddress).decimals()
        );

        require(decimalsRewardToken < 30, "Must be inferior to 30");

        PRECISION_FACTOR = uint256(
            10 ** (uint256(30).sub(decimalsRewardToken))
        );

        // Set the lastRewardTimeStamp as the startTimeStamp
        lastRewardTimeStamp = startTimeStamp;
    }

    function depositReward(uint256 _amount) external onlyOwner {
        stakedToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
    }

    /*
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function deposit(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        _updatePool();

        if (hasUserLimit) {
            require(
                _amount.add(user.amount) <= poolLimitPerUser,
                "User amount above limit"
            );
        }

        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(accTokenPerShare)
                .div(PRECISION_FACTOR)
                .sub(user.rewardDebt);
            if (pending > 0) {
                rewardToken.safeTransfer(address(msg.sender), pending);
            }
        }

        if (_amount > 0) {
            user.amount = user.amount.add(_amount);
            stakedToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
        }

        stakedTokenSupply += _amount;

        user.lastDepositTimeStamp = block.timestamp;

        user.rewardDebt = user.amount.mul(accTokenPerShare).div(
            PRECISION_FACTOR
        );

        emit Deposit(msg.sender, _amount);
    }

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function withdraw(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");

        _updatePool();

        uint256 pending = user
            .amount
            .mul(accTokenPerShare)
            .div(PRECISION_FACTOR)
            .sub(user.rewardDebt);

        if (_amount > 0) {
            if (
                block.timestamp <
                user.lastDepositTimeStamp + lockingDays * 1 seconds
            ) {
                uint256 feeAmount = _amount.mul(withdrawFee) / 100;
                _amount -= feeAmount;

                stakedToken.safeTransfer(feeRecipient, feeAmount);
            }
            user.amount = user.amount.sub(_amount);
            stakedToken.safeTransfer(address(msg.sender), _amount);
        }

        if (pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }

        user.rewardDebt = user.amount.mul(accTokenPerShare).div(
            PRECISION_FACTOR
        );

        emit Withdraw(msg.sender, _amount);
    }

    function claimRewards() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        _updatePool();

        uint256 pending = user
            .amount
            .mul(accTokenPerShare)
            .div(PRECISION_FACTOR)
            .sub(user.rewardDebt);

        if (pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }

        user.rewardDebt = user.amount.mul(accTokenPerShare).div(
            PRECISION_FACTOR
        );
        emit Withdraw(msg.sender, pending);
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(
        address _tokenAddress,
        uint256 _tokenAmount
    ) external onlyOwner {
        require(
            _tokenAddress != address(stakedToken),
            "Cannot be staked token"
        );
        require(
            _tokenAddress != address(rewardToken),
            "Cannot be reward token"
        );

        IERC20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner
     */
    function stopReward() external onlyOwner {
        bonusEndTimeStamp = block.number;
    }

    /*
     * @notice Update pool limit per user
     * @dev Only callable by owner.
     * @param _hasUserLimit: whether the limit remains forced
     * @param _poolLimitPerUser: new pool limit per user
     */
    function updatePoolLimitPerUser(
        bool _hasUserLimit,
        uint256 _poolLimitPerUser
    ) external onlyOwner {
        require(hasUserLimit, "Must be set");
        if (_hasUserLimit) {
            require(
                _poolLimitPerUser > poolLimitPerUser,
                "New limit must be higher"
            );
            poolLimitPerUser = _poolLimitPerUser;
        } else {
            hasUserLimit = _hasUserLimit;
            poolLimitPerUser = 0;
        }
        emit NewPoolLimit(poolLimitPerUser);
    }

    /*
     * @notice Update reward per time unit
     * @dev Only callable by owner.
     * @param _rewardPerTimeUnit: the reward per time unit
     */
    function updateRewardPerTimeUnit(
        uint256 _rewardPerTimeUnit
    ) external onlyOwner {
        require(block.timestamp < startTimeStamp, "Pool has started");
        rewardPerTimeUnit = _rewardPerTimeUnit;
        emit NewRewardPerTimeUnit(_rewardPerTimeUnit);
    }

    /**
     * @notice It allows the admin to update start and end timestamps
     * @dev This function is only callable by owner.
     * @param _startTimeStamp: the new start timestamp
     * @param _bonusEndTimeStamp: the new end timestamp
     */
    function updateStartAndEndTimeStamps(
        uint256 _startTimeStamp,
        uint256 _bonusEndTimeStamp
    ) external onlyOwner {
        require(block.timestamp < startTimeStamp, "Pool has started");
        require(
            _startTimeStamp < _bonusEndTimeStamp,
            "New startTimeStamp must be lower than new endTimeStamp"
        );
        require(
            block.timestamp < _startTimeStamp,
            "New startTimeStamp must be higher than current timestamp"
        );

        startTimeStamp = _startTimeStamp;
        bonusEndTimeStamp = _bonusEndTimeStamp;

        // Set the lastRewardTimeStamp as the startTimeStamp
        lastRewardTimeStamp = startTimeStamp;

        emit NewStartAndEndTimeStamps(_startTimeStamp, _bonusEndTimeStamp);
    }

    /*
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        if (block.timestamp > lastRewardTimeStamp && stakedTokenSupply != 0) {
            uint256 multiplier = _getMultiplier(
                lastRewardTimeStamp,
                block.timestamp
            );
            uint256 arshReward = multiplier.mul(rewardPerTimeUnit);
            uint256 adjustedTokenPerShare = accTokenPerShare.add(
                arshReward.mul(PRECISION_FACTOR).div(stakedTokenSupply)
            );
            return
                user
                    .amount
                    .mul(adjustedTokenPerShare)
                    .div(PRECISION_FACTOR)
                    .sub(user.rewardDebt);
        } else {
            return
                user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(
                    user.rewardDebt
                );
        }
    }

    function rewardTokenSupply() public view returns (uint256) {
        return rewardToken.balanceOf(address(this)) - stakedTokenSupply;
    }

    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.timestamp <= lastRewardTimeStamp) {
            return;
        }

        if (stakedTokenSupply == 0) {
            lastRewardTimeStamp = block.timestamp;
            return;
        }

        uint256 multiplier = _getMultiplier(
            lastRewardTimeStamp,
            block.timestamp
        );
        uint256 arshReward = multiplier.mul(rewardPerTimeUnit);
        accTokenPerShare = accTokenPerShare.add(
            arshReward.mul(PRECISION_FACTOR).div(stakedTokenSupply)
        );
        lastRewardTimeStamp = block.timestamp;
    }

    /*
     * @notice Return reward multiplier over the given _from to _to timestamp.
     * @param _from: timestamp to start
     * @param _to: timestamp to finish
     */
    function _getMultiplier(
        uint256 _from,
        uint256 _to
    ) internal view returns (uint256) {
        if (_to <= bonusEndTimeStamp) {
            return _to.sub(_from);
        } else if (_from >= bonusEndTimeStamp) {
            return 0;
        } else {
            return bonusEndTimeStamp.sub(_from);
        }
    }
}

