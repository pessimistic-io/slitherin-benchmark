// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./AccessControlUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

contract MultiRewardStakerUpgradeable is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    // Role to allow basic/quick admin tasks (add new token, update reward rate)
    bytes32 public constant OPERATOR = keccak256("OPERATOR_ROLE");

    uint256 public constant DEPOSIT_FEE = 100;

    uint256 public startTime;

    uint256 public endTime;

    uint256 public lastRewardTime;

    IERC20MetadataUpgradeable public stakedToken;

    address public treasury;

    mapping(address => UserInfo) public userInfo;

    EnumerableSetUpgradeable.AddressSet internal _rewardTokenAddresses;

    mapping(address => RewardInfo) internal _rewardInfo;

    mapping(address => mapping(address => uint256)) public userRewardDebts;

    struct UserInfo {
        uint256 amount;
    }

    struct RewardInfo {
        uint256 accTokenPerShare;
        uint256 rewardPerSecond;
        uint256 startTime;
        uint256 PRECISION_FACTOR;
    }

    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartAndEndTime(uint256 startTime, uint256 endTime);
    event NewRewardPerSecond(address token, uint256 rewardPerBlock);
    event TokenRecovery(address indexed token, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event RewardAdded(address token, uint256 startTime, uint256 ratePerSecond);
    event RewardsStop(uint256 blockTime);

    modifier onlyOwner() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Ownable: Caller is not the owner");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR, msg.sender), "Only operator");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20MetadataUpgradeable _stakedToken,
        IERC20MetadataUpgradeable[] calldata _rewardTokens,
        uint256[] calldata _startTimes,
        uint256[] calldata _rewardsPerSecond,
        uint256 _startTime,
        uint256 _endTime,
        address _treasury
    ) public initializer {
        require(_treasury != address(0), "Treasury not provided");

        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _treasury);
        _grantRole(OPERATOR, _treasury); // Make role admin to allow revoking any operator account
        _grantRole(OPERATOR, msg.sender);

        stakedToken = _stakedToken;
        startTime = _startTime;
        endTime = _endTime;
        treasury = _treasury;

        _addRewards(_rewardTokens, _startTimes, _rewardsPerSecond);

        lastRewardTime = _startTime;
    }

    function deposit(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        _updatePool();

        (address[] memory rewardAddresses, uint256 rewardCount) = _getBaseRewardsInfo();

        if (user.amount > 0) {
            RewardInfo memory reward;
            IERC20MetadataUpgradeable rewardTokenInstance;
            uint256 pending;

            for (uint256 i = 0; i < rewardCount; ) {
                reward = _rewardInfo[rewardAddresses[i]];
                rewardTokenInstance = IERC20MetadataUpgradeable(rewardAddresses[i]);

                pending =
                    (user.amount * reward.accTokenPerShare) /
                    reward.PRECISION_FACTOR -
                    userRewardDebts[msg.sender][rewardAddresses[i]];

                if (pending > 0) {
                    uint256 contractRewardBalance = rewardTokenInstance.balanceOf(address(this));

                    if (pending > contractRewardBalance && contractRewardBalance > 0) {
                        rewardTokenInstance.safeTransfer(address(msg.sender), contractRewardBalance);
                    } else if (pending <= contractRewardBalance) {
                        rewardTokenInstance.safeTransfer(address(msg.sender), pending);
                    }
                }

                unchecked {
                    ++i;
                }
            }
        }

        if (_amount > 0) {
            stakedToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 feeAmount = _amount / DEPOSIT_FEE;
            _amount = _amount - feeAmount;
            user.amount = user.amount + _amount;
            stakedToken.safeTransfer(treasury, feeAmount);
        }

        for (uint256 i = 0; i < rewardCount; ) {
            RewardInfo memory reward = _rewardInfo[rewardAddresses[i]];
            userRewardDebts[msg.sender][rewardAddresses[i]] =
                (user.amount * reward.accTokenPerShare) /
                reward.PRECISION_FACTOR;

            unchecked {
                ++i;
            }
        }

        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");

        _updatePool();

        address[] memory rewardAddresses = _rewardTokenAddresses.values();
        uint256 rewardCount = rewardAddresses.length;

        if (user.amount > 0) {
            RewardInfo memory reward;
            IERC20MetadataUpgradeable rewardTokenInstance;
            uint256 pending;

            for (uint256 i = 0; i < rewardCount; ) {
                reward = _rewardInfo[rewardAddresses[i]];
                rewardTokenInstance = IERC20MetadataUpgradeable(rewardAddresses[i]);
                pending =
                    (user.amount * reward.accTokenPerShare) /
                    reward.PRECISION_FACTOR -
                    userRewardDebts[msg.sender][rewardAddresses[i]];

                if (pending > 0) {
                    uint256 contractRewardBalance = rewardTokenInstance.balanceOf(address(this));

                    if (pending > contractRewardBalance && contractRewardBalance > 0) {
                        rewardTokenInstance.safeTransfer(address(msg.sender), contractRewardBalance);
                    } else if (pending <= contractRewardBalance) {
                        rewardTokenInstance.safeTransfer(address(msg.sender), pending);
                    }
                }

                unchecked {
                    ++i;
                }
            }
        }

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            stakedToken.safeTransfer(address(msg.sender), _amount);
        }

        for (uint256 i = 0; i < rewardCount; ) {
            RewardInfo memory reward = _rewardInfo[rewardAddresses[i]];
            userRewardDebts[msg.sender][rewardAddresses[i]] =
                (user.amount * reward.accTokenPerShare) /
                reward.PRECISION_FACTOR;

            unchecked {
                ++i;
            }
        }

        emit Withdraw(msg.sender, _amount);
    }

    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amountToTransfer = user.amount;
        user.amount = 0;

        address[] memory rewardAddresses = _rewardTokenAddresses.values();
        uint256 rewardCount = rewardAddresses.length;

        for (uint256 i = 0; i < rewardCount; ) {
            userRewardDebts[msg.sender][rewardAddresses[i]] = 0;

            unchecked {
                ++i;
            }
        }

        if (amountToTransfer > 0) {
            stakedToken.safeTransfer(address(msg.sender), amountToTransfer);
        }

        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    function updatePool() external {
        _updatePool();
    }

    // ========================================================================= //
    // ================================= VIEW ================================== //
    // ========================================================================= //

    function pendingReward(
        address _user
    ) external view returns (address[] memory tokens, uint256[] memory rewardAmounts) {
        UserInfo storage user = userInfo[_user];

        (address[] memory rewardAddresses, uint256 rewardCount) = _getBaseRewardsInfo();

        tokens = rewardAddresses;
        rewardAmounts = new uint256[](rewardCount);

        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));

        RewardInfo memory reward;
        uint256 fromTime;
        uint256 rewardAmount;
        uint256 adjustedTokenPerShare;

        for (uint256 i = 0; i < rewardCount; ) {
            reward = _rewardInfo[rewardAddresses[i]];

            if (block.timestamp > lastRewardTime && stakedTokenSupply != 0 && block.timestamp > reward.startTime) {
                fromTime = reward.startTime > lastRewardTime ? reward.startTime : lastRewardTime;
                rewardAmount = reward.rewardPerSecond * _getMultiplier(fromTime, block.timestamp);

                adjustedTokenPerShare =
                    reward.accTokenPerShare +
                    (rewardAmount * reward.PRECISION_FACTOR) /
                    stakedTokenSupply;

                rewardAmounts[i] =
                    (user.amount * adjustedTokenPerShare) /
                    reward.PRECISION_FACTOR -
                    userRewardDebts[_user][rewardAddresses[i]];
            } else {
                rewardAmounts[i] =
                    (user.amount * reward.accTokenPerShare) /
                    reward.PRECISION_FACTOR -
                    userRewardDebts[_user][rewardAddresses[i]];
            }

            unchecked {
                ++i;
            }
        }
    }

    function getRewardTokensInfo() external view returns (address[] memory tokens, RewardInfo[] memory rewards) {
        (address[] memory rewardAddresses, uint256 rewardCount) = _getBaseRewardsInfo();

        tokens = rewardAddresses;
        rewards = new RewardInfo[](rewardCount);

        for (uint256 i = 0; i < rewardCount; i++) {
            rewards[i] = _rewardInfo[rewardAddresses[i]];
        }
    }

    // ========================================================================= //
    // =============================== INTERNAL ================================ //
    // ========================================================================= //

    function _updatePool() internal {
        if (block.timestamp <= lastRewardTime) {
            return;
        }

        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));

        if (stakedTokenSupply == 0) {
            lastRewardTime = block.timestamp;
            return;
        }

        (address[] memory rewardAddresses, uint256 rewardCount) = _getBaseRewardsInfo();
        uint256 fromTime;
        uint256 rewardAmount;
        uint256 _startTime;

        for (uint256 i = 0; i < rewardCount; ) {
            RewardInfo storage reward = _rewardInfo[rewardAddresses[i]];
            _startTime = reward.startTime;

            if (block.timestamp >= _startTime) {
                fromTime = _startTime > lastRewardTime ? _startTime : lastRewardTime;
                rewardAmount = reward.rewardPerSecond * _getMultiplier(fromTime, block.timestamp);
                reward.accTokenPerShare += (rewardAmount * reward.PRECISION_FACTOR) / stakedTokenSupply;
            }

            unchecked {
                ++i;
            }
        }

        lastRewardTime = block.timestamp;
    }

    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= endTime) {
            return _to - _from;
        } else if (_from >= endTime) {
            return 0;
        } else {
            return endTime - _from;
        }
    }

    function _getBaseRewardsInfo() internal view returns (address[] memory rewardAddresses, uint256 rewardCount) {
        rewardAddresses = _rewardTokenAddresses.values();
        rewardCount = rewardAddresses.length;
    }

    // ========================================================================= //
    // ============================ ADMIN/TREASURY ============================= //
    // ========================================================================= //

    function emergencyRewardWithdraw() external onlyOwner {
        address[] memory rewardAddresses = _rewardTokenAddresses.values();
        uint256 rewardCount = rewardAddresses.length;

        IERC20MetadataUpgradeable reward;
        for (uint256 i = 0; i < rewardCount; ) {
            reward = IERC20MetadataUpgradeable(rewardAddresses[i]);
            reward.safeTransfer(msg.sender, reward.balanceOf(address(this)));

            unchecked {
                ++i;
            }
        }
    }

    function recoverToken(address _token) external onlyOwner {
        require(_token != address(stakedToken), "Operations: Cannot recover staked token");

        uint256 balance = IERC20MetadataUpgradeable(_token).balanceOf(address(this));
        require(balance != 0, "Operations: Cannot recover zero balance");

        IERC20MetadataUpgradeable(_token).safeTransfer(address(msg.sender), balance);

        emit TokenRecovery(_token, balance);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Address cannot be null");
        require(_treasury != treasury, "Address provided is the same as current");
        treasury = _treasury;
    }

    function stopReward() external onlyOwner {
        endTime = block.timestamp;
    }

    function updateStartAndEndTimes(uint256 _startTime, uint256 _endTime) external onlyOwner {
        require(block.timestamp < startTime, "Pool already started");
        require(_startTime < _endTime, "_startTime > _endTime");
        require(block.timestamp < _startTime, "_startTime must be > than current block time");

        startTime = _startTime;
        endTime = _endTime;

        lastRewardTime = _startTime;

        emit NewStartAndEndTime(_startTime, _endTime);
    }

    // ========================================================================= //
    // ============================ ADMIN/OPERATOR ============================= //
    // ========================================================================= //

    function addReward(
        IERC20MetadataUpgradeable _rewardToken,
        uint256 _startTime,
        uint256 _rewardPerSecond
    ) external onlyOperator {
        _addRewardToken(_rewardToken, _startTime, _rewardPerSecond);
    }

    function updateRewardPerSecond(address rewardToken, uint256 _rewardPerSecond) external onlyOperator {
        require(rewardToken != address(0), "Reward address zero");
        require(_rewardTokenAddresses.contains(rewardToken), "Token not added");

        _rewardInfo[rewardToken].rewardPerSecond = _rewardPerSecond;
        emit NewRewardPerSecond(rewardToken, _rewardPerSecond);
    }

    function _addRewards(
        IERC20MetadataUpgradeable[] calldata rewardTokens,
        uint256[] calldata startTimes,
        uint256[] calldata rewardsPerSecond
    ) internal {
        uint256 rewardCount = rewardTokens.length;
        require(startTimes.length == rewardCount && rewardsPerSecond.length == rewardCount, "Array lengths mismatched");

        for (uint256 i = 0; i < rewardCount; ) {
            _addRewardToken(rewardTokens[i], startTimes[i], rewardsPerSecond[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _addRewardToken(
        IERC20MetadataUpgradeable _rewardToken,
        uint256 _startTime,
        uint256 _rewardPerSecond
    ) internal {
        require(address(_rewardToken) != address(0), "Reward address zero");
        require(!_rewardTokenAddresses.contains(address(_rewardToken)), "Token already added");
        require(_startTime >= block.timestamp, "Reward start time in past");

        uint256 decimalsRewardToken = uint256(_rewardToken.decimals());
        require(decimalsRewardToken < 30, "Must be less than 30");

        _rewardTokenAddresses.add(address(_rewardToken));

        _rewardInfo[address(_rewardToken)] = RewardInfo({
            accTokenPerShare: 0,
            rewardPerSecond: _rewardPerSecond,
            startTime: _startTime,
            PRECISION_FACTOR: uint256(10 ** (uint256(30) - decimalsRewardToken))
        });

        emit RewardAdded(address(_rewardToken), _startTime, _rewardPerSecond);
    }
}

