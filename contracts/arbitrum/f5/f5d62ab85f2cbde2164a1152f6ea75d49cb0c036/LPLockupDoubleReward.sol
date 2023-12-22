// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "./Ownable.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SafeMath} from "./SafeMath.sol";
import {DuoMaster} from "./DuoMaster.sol";

contract LPLockupDoubleReward is ERC20, Ownable, ReentrancyGuard {
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

    // Reward tokens created per second.
    uint256 public rewardPerSecond;

    // The precision factor
    uint256 public PRECISION_FACTOR;

    // The reward token
    IERC20 public rewardToken;

    // The staked token
    IERC20 public stakedToken;

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => UserInfo) public userInfo;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
    }

    DuoMaster public duoMaster;

    uint256 public lockupPid;
    uint256 public releaseTime;

    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartAndEndTime(uint256 startTimestamp, uint256 endTimestamp);
    event NewRewardPerSecond(uint256 rewardPerSecond);
    event RewardsStop(uint256 timestamp);
    event Withdraw(address indexed user, uint256 amount);

    constructor() ERC20("DUO-USDC LP LOCKUP", "Monopoly LOCKUP") {
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
        DuoMaster _duoMaster,
        uint256 _releaseTime
    ) external {
        require(!isInitialized, "Already initialized");
        require(msg.sender == deployer, "Not deployer");

        // Make this contract initialized
        isInitialized = true;

        stakedToken = _stakedToken;
        rewardToken = _rewardToken;
        rewardPerSecond = _totalRewardAmount.div(
            _bonusEndTimestamp.sub(_startTimestamp)
        );
        startTimestamp = _startTimestamp;
        bonusEndTimestamp = _bonusEndTimestamp;

        uint256 decimalsRewardToken = uint256(
            ERC20(address(rewardToken)).decimals()
        );
        require(decimalsRewardToken < 30, "Must be inferior to 30");

        PRECISION_FACTOR = uint256(
            10 ** (uint256(30).sub(decimalsRewardToken))
        );

        // Set the lastRewardTimestamp as the startTimestamp
        lastRewardTimestamp = startTimestamp;

        duoMaster = _duoMaster;
        releaseTime = _releaseTime;

        _approve(address(this), address(_duoMaster), type(uint256).max);
    }

    function setLockupPid(uint256 _lockupPid) external onlyOwner {
        lockupPid = _lockupPid;
    }

    /*
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to withdraw (in rewardToken)
     * @param _lockPeriod: Lock period (in second)
     */
    function deposit(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        _updatePool();

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
            stakedToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            _mint(address(this), _amount);
            duoMaster.deposit(lockupPid, _amount, msg.sender, address(0));

            user.amount = user.amount.add(_amount);
        }

        user.rewardDebt = user.amount.mul(accTokenPerShare).div(
            PRECISION_FACTOR
        );

        emit Deposit(msg.sender, _amount);
    }

    /*
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

    function emergencyStakedWithdraw(uint256 _amount) external onlyOwner {
        stakedToken.safeTransfer(address(msg.sender), _amount);
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
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply = totalSupply();
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

        return reward;
    }

    // View function to see if user can withdraw staked token.
    function canWithdraw(address _user) external view returns (bool) {
        return block.timestamp >= releaseTime;
    }

    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        uint256 stakedTokenSupply = totalSupply();

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

    // Withdraw invokes _beforeTokenTransfer
    //
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (from != address(this)) {
            require(block.timestamp >= releaseTime, "Can't withdraw yet");
            UserInfo storage user = userInfo[to];
            require(user.amount >= amount, "Amount to withdraw too high");

            _updatePool();

            uint256 pending = user
                .amount
                .mul(accTokenPerShare)
                .div(PRECISION_FACTOR)
                .sub(user.rewardDebt);

            if (pending > 0) {
                rewardToken.safeTransfer(to, pending);
            }

            user.amount = user.amount.sub(amount);

            user.rewardDebt = user.amount.mul(accTokenPerShare).div(
                PRECISION_FACTOR
            );
        }

        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._afterTokenTransfer(from, to, amount);

        if (from != address(this)) {
            // burn
            _burn(to, amount);
            // return lp to user
            stakedToken.safeTransfer(to, amount);
        }
    }
}

