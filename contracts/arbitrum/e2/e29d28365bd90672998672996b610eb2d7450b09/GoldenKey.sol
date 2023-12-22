// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "./Ownable.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SafeMath} from "./SafeMath.sol";

contract GoldenKey is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // The address of the deployer
    address public deployer;

    // Whether it is initialized
    bool public isInitialized;

    // Accrued token per share
    uint256 public accTokenPerShare;

    // The timestamp when mining ends.
    uint256 public bonusEndTimestamp;

    // The timestamp when mining starts.
    uint256 public startTimestamp;

    // The timestamp of the last pool update
    uint256 public lastRewardTimestamp;

    // The pool limit (0 if none)
    uint256 public poolLimitPerUser;

    // Reward tokens created per second.
    uint256 public rewardPerSecond;

    // The precision factor
    uint256 public PRECISION_FACTOR;

    // The reward token
    IERC20 public rewardToken;

    // The staked token
    IERC20 public stakedToken;

    // The amount of staked token
    uint256 public totalStakedTokenAmount = 0;

    // The amount of rewarded token
    uint256 public totalRewardedTokenAmount = 0;

    // The max withdrawal interval
    uint256 public maxMaxWithdrawalInterval;

    // The incentive for max withdrawal lock;
    uint256 public incentiveRateForMaxWithdrawalLock;

    // Max withdrawal interval: 100 days.
    uint256 public constant MAXIMUM_WITHDRAWAL_INTERVAL = 100 days;

    // Min lock interval for incentive
    uint256 public constant minLockPeriod = 0 days;

    // If is using lock
    bool isLockOn = true;

    address public feeAddr;
    uint16 public withdrawalFeeBP = 0;
    uint256 public depositFeeAmount = 0;
    uint16 public constant MAX_WITHDRAWAL_FEE_BP = 400;
    uint16 public constant MAX_DEPOSIT_FEE_BP = 400;

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => UserInfo) public userInfo;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
        uint256 nextWithdrawalUntil; // When can the user withdraw again.
        uint256 lockPeriod; // The lock period user selected.
    }

    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartAndEndTime(uint256 startTimestamp, uint256 endTimestamp);
    event NewRewardPerSecond(uint256 rewardPerSecond);
    event RewardsStop(uint256 timestamp);
    event Withdraw(address indexed user, uint256 amount);
    event NewMaxWithdrawalInterval(uint256 interval);
    event NewIncentiveRateForMaxWithdrawalLock(uint16 rate);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDepositFeeAmount(uint256 depositFeeAmount);
    event SetWithdrawFeeBP(uint16 withdrawalFeeBP);
    event LockOn(bool isLocked);

    constructor() {
        deployer = msg.sender;
    }

    /*
     * @notice Initialize the contract
     * @param _stakedToken: staked token address
     * @param _rewardToken: reward token address
     * @param _rewardPerSecond: reward per second (in rewardToken)
     * @param _startTimestamp: start timestamp
     * @param _bonusEndTimestamp: end timestamp
     * @param _maxMaxWithdrawalInterval: the withdrawal interval for stakedToken (if any, else 0)
     * @param _admin: admin address with ownership
     */
    function initialize(
        IERC20 _stakedToken,
        IERC20 _rewardToken,
        uint256 _totalRewardAmount,
        uint256 _startTimestamp,
        uint256 _bonusEndTimestamp,
        // uint256 _maxMaxWithdrawalInterval,
        // uint16 _incentiveRateForMaxWithdrawalLock,
        // uint16 _withdrawalFeeBP,
        // uint256 _depositFeeAmount,
        address _feeAddr,
        address _admin
    ) external {
        require(!isInitialized, "Already initialized");
        require(msg.sender == deployer, "Not deployer");
        // require(
        //     _maxMaxWithdrawalInterval <= MAXIMUM_WITHDRAWAL_INTERVAL,
        //     "Invalid withdrawal interval"
        // );

        // Make this contract initialized
        isInitialized = true;

        stakedToken = _stakedToken;
        rewardToken = _rewardToken;
        rewardPerSecond = _totalRewardAmount.div(
            _bonusEndTimestamp.sub(_startTimestamp)
        );
        startTimestamp = _startTimestamp;
        bonusEndTimestamp = _bonusEndTimestamp;
        // maxMaxWithdrawalInterval = _maxMaxWithdrawalInterval;
        // incentiveRateForMaxWithdrawalLock = _incentiveRateForMaxWithdrawalLock;
        // withdrawalFeeBP = _withdrawalFeeBP;
        // depositFeeAmount = _depositFeeAmount;

        uint256 decimalsRewardToken = uint256(
            ERC20(address(rewardToken)).decimals()
        );
        require(decimalsRewardToken < 30, "Must be inferior to 30");

        PRECISION_FACTOR = uint256(
            10 ** (uint256(30).sub(decimalsRewardToken))
        );

        // Set the lastRewardTimestamp as the startTimestamp
        lastRewardTimestamp = startTimestamp;

        // Transfer ownership to the admin address who becomes owner of the contract
        transferOwnership(_admin);

        feeAddr = _feeAddr;
    }

    /*
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to withdraw (in rewardToken)
     * @param _lockPeriod: Lock period (in second)
     */
    function deposit(
        uint256 _amount
    )
        external
        // uint256 _lockPeriod
        nonReentrant
    {
        uint256 _lockPeriod = 0;

        UserInfo storage user = userInfo[msg.sender];

        totalStakedTokenAmount = totalStakedTokenAmount.add(_amount);

        _updatePool();

        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(accTokenPerShare)
                .div(PRECISION_FACTOR)
                .sub(user.rewardDebt);
            pending = pending.add(
                pending.mul(incentiveRateForLockPeriod(user.lockPeriod)).div(
                    10000
                )
            );
            if (pending > 0) {
                rewardToken.safeTransfer(address(msg.sender), pending);
                totalRewardedTokenAmount = totalRewardedTokenAmount.add(
                    pending
                );
            }
        }

        if (_amount > 0) {
            require(
                _lockPeriod >= minLockPeriod,
                "The lock period is too short"
            );
            require(
                _lockPeriod <= maxMaxWithdrawalInterval,
                "The lock period is too long"
            );
            require(
                block.timestamp.add(_lockPeriod) > user.nextWithdrawalUntil,
                "The lock period cannot be shorten than existing lock"
            );

            if (depositFeeAmount > 0) {
                _amount = _amount.sub(depositFeeAmount);
                stakedToken.safeTransferFrom(
                    address(msg.sender),
                    address(feeAddr),
                    depositFeeAmount
                );
            }
            uint256 wantBalBefore = IERC20(stakedToken).balanceOf(
                address(this)
            );
            stakedToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            uint256 wantBalAfter = IERC20(stakedToken).balanceOf(address(this));
            _amount = wantBalAfter.sub(wantBalBefore);
            user.amount = user.amount.add(_amount);

            user.nextWithdrawalUntil = block.timestamp.add(_lockPeriod);
            user.lockPeriod = _lockPeriod;
        }

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
        if (isLockOn)
            require(
                user.nextWithdrawalUntil <= block.timestamp,
                "Withdrawal locked"
            );

        _updatePool();

        uint256 pending = user
            .amount
            .mul(accTokenPerShare)
            .div(PRECISION_FACTOR)
            .sub(user.rewardDebt);

        if (_amount > 0) {
            if (getWithdrawalFeeBP(msg.sender) > 0) {
                uint256 withdrawalFee = _amount.mul(withdrawalFeeBP).div(10000);
                user.amount = user.amount.sub(withdrawalFee);
                _amount = _amount.sub(withdrawalFee);
                stakedToken.safeTransfer(address(feeAddr), withdrawalFee);
            }
            user.amount = user.amount.sub(_amount);
            stakedToken.safeTransfer(address(msg.sender), _amount);
            totalStakedTokenAmount = totalStakedTokenAmount.sub(_amount);
        }

        if (pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pending);
            totalRewardedTokenAmount = totalRewardedTokenAmount.add(pending);
            //user.nextWithdrawalUntil = block.timestamp.add(maxMaxWithdrawalInterval);
        }

        user.rewardDebt = user.amount.mul(accTokenPerShare).div(
            PRECISION_FACTOR
        );

        emit Withdraw(msg.sender, _amount);
    }

    /*
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyStakeWithdraw(uint256 _amount) external onlyOwner {
        stakedToken.safeTransfer(address(msg.sender), _amount);
    }

    /*
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
        bonusEndTimestamp = block.timestamp;
    }

    function updateEndTimestamp(uint256 _bonusEndTimestamp) external onlyOwner {
        require(block.timestamp < bonusEndTimestamp, "Pool has already ended");
        _updatePool();
        bonusEndTimestamp = _bonusEndTimestamp;
    }

    /*
     * @notice Update reward per second
     * @dev Only callable by owner.
     * @param _rewardPerSecond: the reward per second
     */
    function updateRewardPerSecond(
        uint256 _rewardPerSecond
    ) external onlyOwner {
        _updatePool();

        rewardPerSecond = _rewardPerSecond;
        emit NewRewardPerSecond(_rewardPerSecond);
    }

    /**
     * @notice It allows the admin to update start and end timestamp
     * @dev This function is only callable by owner.
     * @param _startTimestamp: the new start timestamp
     * @param _bonusEndTimestamp: the new end timestamp
     */
    function updateStartAndEndTimestamps(
        uint256 _startTimestamp,
        uint256 _bonusEndTimestamp
    ) external onlyOwner {
        require(block.timestamp < startTimestamp, "Pool has started");
        require(
            _startTimestamp < _bonusEndTimestamp,
            "New startTimestamp must be lower than new endTimestamp"
        );
        require(
            block.timestamp < _startTimestamp,
            "New startTimestamp must be higher than now"
        );

        startTimestamp = _startTimestamp;
        bonusEndTimestamp = _bonusEndTimestamp;

        // Set the lastRewardTimestamp as the startTimestamp
        lastRewardTimestamp = startTimestamp;

        emit NewStartAndEndTime(_startTimestamp, _bonusEndTimestamp);
    }

    /*
     * @notice Update the withdrawal interval
     * @dev Only callable by owner.
     * @param _interval: the withdrawal interval for staked token in seconds
     */
    function updateMaxMaxWithdrawalInterval(
        uint256 _interval
    ) external onlyOwner {
        require(
            _interval <= MAXIMUM_WITHDRAWAL_INTERVAL,
            "Invalid withdrawal interval"
        );
        maxMaxWithdrawalInterval = _interval;
        emit NewMaxWithdrawalInterval(_interval);
    }

    /*
     * @notice Update the incentive rate for max withdrawal lock interval
     * @dev Only callable by owner.
     * @param _rate: the incentive rate for max withdrawal lock interval
     */
    function updateIncentiveRateForMaxWithdrawalLock(
        uint16 _rate
    ) external onlyOwner {
        incentiveRateForMaxWithdrawalLock = _rate;
        emit NewIncentiveRateForMaxWithdrawalLock(_rate);
    }

    function setFeeAddress(address _feeAddress) public onlyOwner {
        feeAddr = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function setDepositFee(uint256 _depositFeeAmount) external onlyOwner {
        depositFeeAmount = _depositFeeAmount;
        emit SetDepositFeeAmount(_depositFeeAmount);
    }

    function setWithdrawFee(uint16 _withdrawalFeeBP) external onlyOwner {
        require(
            _withdrawalFeeBP <= MAX_WITHDRAWAL_FEE_BP,
            "setWithdrawFee: invalid deposit fee basis points"
        );
        withdrawalFeeBP = _withdrawalFeeBP;
        emit SetWithdrawFeeBP(_withdrawalFeeBP);
    }

    function setLockOn(bool _isLockOn) external onlyOwner {
        isLockOn = _isLockOn;
        emit LockOn(_isLockOn);
    }

    /*
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));
        uint256 reward = 0;
        if (block.timestamp > lastRewardTimestamp && stakedTokenSupply != 0) {
            uint256 multiplier = _getMultiplier(
                lastRewardTimestamp,
                block.timestamp
            );
            uint256 rewardTokenReward = multiplier.mul(rewardPerSecond);
            uint256 adjustedTokenPerShare = accTokenPerShare.add(
                rewardTokenReward.mul(PRECISION_FACTOR).div(stakedTokenSupply)
            );
            reward = user
                .amount
                .mul(adjustedTokenPerShare)
                .div(PRECISION_FACTOR)
                .sub(user.rewardDebt);
        } else {
            reward = user
                .amount
                .mul(accTokenPerShare)
                .div(PRECISION_FACTOR)
                .sub(user.rewardDebt);
        }

        return
            reward.add(
                reward.mul(incentiveRateForLockPeriod(user.lockPeriod)).div(
                    10000
                )
            );
    }

    /*
     * @notice View function to see incentive rate for lock period.
     * @param _lockPeriod: lock period
     * @return Incentive rate in 100 multipled value (10000 = 100%)
     */
    function incentiveRateForLockPeriod(
        uint256 _lockPeriod
    ) public view returns (uint256) {
        if (maxMaxWithdrawalInterval == 0) return 0;

        uint256 lockPeriod = _lockPeriod;
        if (_lockPeriod > maxMaxWithdrawalInterval)
            lockPeriod = maxMaxWithdrawalInterval;

        return
            lockPeriod.mul(incentiveRateForMaxWithdrawalLock).div(
                maxMaxWithdrawalInterval
            );
    }

    // View function to see if user can withdraw staked token.
    function canWithdraw(address _user) external view returns (bool) {
        UserInfo storage user = userInfo[_user];
        return block.timestamp >= user.nextWithdrawalUntil;
    }

    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));

        if (stakedTokenSupply == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 multiplier = _getMultiplier(
            lastRewardTimestamp,
            block.timestamp
        );
        uint256 rewardTokenReward = multiplier.mul(rewardPerSecond);
        accTokenPerShare = accTokenPerShare.add(
            rewardTokenReward.mul(PRECISION_FACTOR).div(stakedTokenSupply)
        );
        lastRewardTimestamp = block.timestamp;
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
        if (_to <= bonusEndTimestamp) {
            return _to.sub(_from);
        } else if (_from >= bonusEndTimestamp) {
            return 0;
        } else {
            return bonusEndTimestamp.sub(_from);
        }
    }

    function getWithdrawalFeeBP(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        if (
            block.timestamp < user.nextWithdrawalUntil &&
            block.timestamp < bonusEndTimestamp
        ) {
            return withdrawalFeeBP;
        }
        return 0;
    }
}

