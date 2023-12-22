// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./AccessControl.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";

import "./IXARXStaker.sol";

contract xARXStaker is AccessControl, ReentrancyGuard, IXARXStaker {
    using SafeERC20 for IERC20Metadata;

    bytes32 public OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => UserInfo) public userInfo;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        mapping(IERC20Metadata => uint256) rewardDebts; // Reward debts for each rewardToken
    }

    struct Reward {
        uint256 accTokenPerShare;
        uint256 PRECISION_FACTOR;
        uint256 rewardPerSec;
    }

    // The staked token
    IERC20Metadata public stakedToken;
    // List of reward tokens
    IERC20Metadata[] public rewardTokensList;

    mapping(IERC20Metadata => Reward) public rewardTokens;

    // The block time of the last pool update
    uint256 public lastRewardTime;

    // Whether it is initialized
    bool public isInitialized;

    // The block time when Reward mining ends.
    uint256 public endTime;

    // The block time when Reward mining starts.
    uint256 public startTime;

    // The address that should receive deposit fee
    address public treasury;

    // The fee that is associated with a deposit
    uint256 public depositFee = 100;

    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartAndEndTimes(uint256 startTime, uint256 endTime);
    event NewRewardPerSec(uint256 rewardPerSec);
    event RewardsStop(uint256 blockNumber);
    event TokenRecovery(address indexed token, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == treasury, "Only Owner");
        _;
    }

    constructor(address _treasury) {
        require(_treasury != address(0), "Treasury not provided");

        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, _treasury);
        _grantRole(OPERATOR_ROLE, _treasury);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    // ================================ STATE TRANSISTIONS =============================== //

    /*
     * @notice Initialize the contract
     * @param _stakedToken: staked token address
     * @param _rewardToken: reward token address
     * @param _rewardPerSec: reward per sec (in rewardToken)
     * @param _startTime: start time
     * @param _endTime: end time
     */
    function initialize(
        IERC20Metadata _stakedToken,
        IERC20Metadata[] memory _rewardTokens,
        uint256[] memory _rewardsPerSec,
        uint256 _startTime,
        uint256 _endTime
    ) external returns (bool) {
        require(!isInitialized, "Already initialized");
        require(hasRole(OPERATOR_ROLE, msg.sender), "Only operator");

        // Make this contract initialized
        isInitialized = true;

        stakedToken = _stakedToken;
        startTime = _startTime;
        endTime = _endTime;

        // Set the lastRewardTime as the startTime
        lastRewardTime = startTime;

        _addRewardTokens(_rewardTokens, _rewardsPerSec);

        return true;
    }

    /*
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to stake
     */
    function deposit(uint256 _amount) external override nonReentrant returns (bool) {
        UserInfo storage user = userInfo[msg.sender];

        _updatePool();

        uint256 rewardCount = rewardTokensList.length;

        if (user.amount > 0) {
            IERC20Metadata rewardToken;
            Reward memory rewardInfo;

            for (uint256 i = 0; i < rewardCount; ) {
                rewardToken = rewardTokensList[i];
                rewardInfo = rewardTokens[rewardToken];

                uint256 pending = (user.amount * rewardInfo.accTokenPerShare) /
                    rewardInfo.PRECISION_FACTOR -
                    user.rewardDebts[rewardToken];

                _safeRewardsTransfer(rewardToken, pending);

                unchecked {
                    ++i;
                }
            }
        }

        if (_amount > 0) {
            stakedToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 feeAmount = _amount / depositFee;
            _amount = _amount - feeAmount;
            user.amount = user.amount + _amount;
            stakedToken.safeTransfer(treasury, feeAmount);
        }

        for (uint256 i = 0; i < rewardCount; ) {
            user.rewardDebts[rewardTokensList[i]] =
                (user.amount * rewardTokens[rewardTokensList[i]].accTokenPerShare) /
                rewardTokens[rewardTokensList[i]].PRECISION_FACTOR;

            unchecked {
                ++i;
            }
        }

        emit Deposit(msg.sender, _amount);

        return true;
    }

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw
     */
    function withdraw(uint256 _amount) external override nonReentrant returns (bool) {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");

        _updatePool();

        IERC20Metadata rewardToken;
        Reward memory rewardInfo;
        uint256 rewardCount = rewardTokensList.length;

        for (uint256 i = 0; i < rewardCount; ) {
            rewardToken = rewardTokensList[i];
            rewardInfo = rewardTokens[rewardToken];

            uint256 pending = (user.amount * rewardInfo.accTokenPerShare) /
                rewardInfo.PRECISION_FACTOR -
                user.rewardDebts[rewardToken];

            _safeRewardsTransfer(rewardToken, pending);

            unchecked {
                ++i;
            }
        }

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            stakedToken.safeTransfer(address(msg.sender), _amount);
        }

        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            user.rewardDebts[rewardTokensList[i]] =
                (user.amount * rewardTokens[rewardTokensList[i]].accTokenPerShare) /
                rewardTokens[rewardTokensList[i]].PRECISION_FACTOR;
        }

        emit Withdraw(msg.sender, _amount);

        return true;
    }

    /*
     * @notice Withdraw staked tokens without caring about rewards rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw() external override nonReentrant returns (bool) {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amountToTransfer = user.amount;
        user.amount = 0;

        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            user.rewardDebts[rewardTokensList[i]] = 0;
        }

        if (amountToTransfer > 0) {
            stakedToken.safeTransfer(address(msg.sender), amountToTransfer);
        }

        emit EmergencyWithdraw(msg.sender, user.amount);
        return true;
    }

    // ================================ VIEW =============================== //

    /*
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending rewards for a given user
     */
    function pendingRewards(
        address _user
    ) external view returns (IERC20Metadata[] memory tokens, uint256[] memory rewardAmounts) {
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));

        uint256 rewardCount = rewardTokensList.length;
        tokens = new IERC20Metadata[](rewardCount);
        rewardAmounts = new uint256[](rewardCount);

        IERC20Metadata rewardToken;
        Reward memory rewardInfo;

        for (uint256 i = 0; i < rewardCount; i++) {
            rewardToken = rewardTokensList[i];
            rewardInfo = rewardTokens[rewardToken];
            tokens[i] = rewardToken;

            if (block.timestamp > lastRewardTime && stakedTokenSupply != 0) {
                uint256 multiplier = _getMultiplier(lastRewardTime, block.timestamp);

                uint256 reward_ = multiplier * rewardInfo.rewardPerSec;
                uint256 adjustedTokenPerShare = rewardInfo.accTokenPerShare +
                    (reward_ * rewardInfo.PRECISION_FACTOR) /
                    stakedTokenSupply;

                rewardAmounts[i] =
                    (user.amount * adjustedTokenPerShare) /
                    rewardInfo.PRECISION_FACTOR -
                    user.rewardDebts[rewardToken];
            } else {
                rewardAmounts[i] =
                    (user.amount * rewardInfo.accTokenPerShare) /
                    rewardInfo.PRECISION_FACTOR -
                    user.rewardDebts[rewardToken];
            }
        }
    }

    function getRewardTokens() external view returns (IERC20Metadata[] memory tokens, Reward[] memory rewardInfo) {
        uint256 rewardCount = rewardTokensList.length;
        tokens = new IERC20Metadata[](rewardCount);
        rewardInfo = new Reward[](rewardCount);

        for (uint256 i = 0; i < rewardCount; i++) {
            tokens[i] = rewardTokensList[i];
            rewardInfo[i] = rewardTokens[tokens[i]];
        }
    }

    // ================================ ADMIN =============================== //

    function addRewardTokens(
        IERC20Metadata[] memory _rewardTokens,
        uint256[] memory _rewardsPerSec
    ) external onlyOwner {
        _addRewardTokens(_rewardTokens, _rewardsPerSec);
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(uint256[] memory _amounts) external onlyOwner returns (bool) {
        require(_amounts.length == rewardTokensList.length, "Length of amountsList is not correct");
        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            rewardTokensList[i].safeTransfer(address(msg.sender), _amounts[i]);
        }
        return true;
    }

    /**
     * @notice Allows the owner to recover tokens sent to the contract by mistake
     * @param _token: token address
     * @dev Callable by owner
     */
    function recoverToken(address _token) external onlyOwner returns (bool) {
        require(_token != address(stakedToken), "Operations: Cannot recover staked token");

        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            address _rewardToken = address(rewardTokensList[i]);
            require(_token != address(_rewardToken), "Operations: Cannot recover reward token");
        }

        uint256 balance = IERC20Metadata(_token).balanceOf(address(this));
        require(balance != 0, "Operations: Cannot recover zero balance");

        IERC20Metadata(_token).safeTransfer(address(msg.sender), balance);

        emit TokenRecovery(_token, balance);

        return true;
    }

    /*
     * @notce update the treasury's address
     * @param _treasury: New address that should receive treasury fees
     */
    function setTreasury(address _treasury) external onlyOwner returns (bool) {
        require(_treasury != address(0), "Address cannot be null");
        require(_treasury != treasury, "Address provided is the same as current");
        treasury = _treasury;
        return true;
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner
     */
    function stopReward() external onlyOwner returns (bool) {
        endTime = block.timestamp;
        return true;
    }

    /*
     * @notice Update reward per sec
     * @dev Only callable by owner.
     * @param _index: rewardToken's number on the list
     * @param _rewardPerSec: the reward per sec
     */
    function updateRewardPerSec(uint256 _index, uint256 _rewardPerSec) external onlyRole(OPERATOR_ROLE) returns (bool) {
        rewardTokens[rewardTokensList[_index]].rewardPerSec = _rewardPerSec;
        emit NewRewardPerSec(_rewardPerSec);
        return true;
    }

    /**
     * @notice It allows the owner to update start and end times
     * @dev This function is only callable by owner.
     * @param _startTime: the new start time
     * @param _endTime: the new end time
     */
    function updateStartAndEndTimes(uint256 _startTime, uint256 _endTime) external onlyOwner returns (bool) {
        require(block.timestamp < startTime, "Pool has started");
        require(_startTime < _endTime, "New startTime must be lower than new endTime");
        require(block.timestamp < _startTime, "New startTime must be higher than current time");

        startTime = _startTime;
        endTime = _endTime;

        // Set the lastRewardTime as the startTime
        lastRewardTime = startTime;

        emit NewStartAndEndTimes(_startTime, _endTime);
        return true;
    }

    // ================================ INTERNAL =============================== //

    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.timestamp <= lastRewardTime) {
            return;
        }

        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));

        if (stakedTokenSupply == 0) {
            lastRewardTime = block.timestamp;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardTime, block.timestamp);

        for (uint256 i = 0; i < rewardTokensList.length; i++) {
            uint256 reward_ = multiplier * rewardTokens[rewardTokensList[i]].rewardPerSec;
            rewardTokens[rewardTokensList[i]].accTokenPerShare +=
                (reward_ * rewardTokens[rewardTokensList[i]].PRECISION_FACTOR) /
                stakedTokenSupply;
        }

        lastRewardTime = block.timestamp;
    }

    function _addRewardTokens(IERC20Metadata[] memory _rewardTokens, uint256[] memory _rewardsPerSec) internal {
        require(_rewardsPerSec.length == _rewardTokens.length, "Length of RewardList is not correct");

        uint256 rewardCount = _rewardTokens.length;

        for (uint256 i = 0; i < rewardCount; ) {
            uint256 decimalsRewardToken = uint256(_rewardTokens[i].decimals());
            require(decimalsRewardToken < 30, "Must be less than 30");
            uint256 PRECISION_FACTOR = uint256(10 ** (uint256(30) - decimalsRewardToken));
            rewardTokensList.push(_rewardTokens[i]);
            rewardTokens[_rewardTokens[i]].PRECISION_FACTOR = PRECISION_FACTOR;
            rewardTokens[_rewardTokens[i]].rewardPerSec = _rewardsPerSec[i];

            unchecked {
                ++i;
            }
        }
    }

    /*
     * @notice Return reward multiplier over the given _from to _to .
     * @param _from: time to start
     * @param _to: time to finish
     */
    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= endTime) {
            return _to - _from;
        } else if (_from >= endTime) {
            return 0;
        } else {
            return endTime - _from;
        }
    }

    /**
     * @dev Safe token transfer function, in case rounding error causes pool to not have enough tokens
     */
    function _safeRewardsTransfer(IERC20Metadata token, uint256 amount) internal {
        uint256 balance = token.balanceOf(address(this));

        if (balance == 0) return;

        // Cap to available balance
        if (amount > balance) {
            amount = balance;
        }

        token.safeTransfer(msg.sender, amount);
    }
}

