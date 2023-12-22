// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./Math.sol";
import "./IERC20.sol";

interface ITowerPoolFactory {
    function emitDeposit(address account, uint256 amount) external;

    function emitWithdraw(address account, uint256 amount) external;
}

// TowerPools are used for rewards, they emit reward tokens over 7 days for staked tokens
contract TowerPool {
    address public stake; // the token that needs to be staked for rewards
    address public factory; // the TowerPoolFactory

    uint256 internal constant DURATION = 7 days; // rewards are released over 7 days
    uint256 internal constant PRECISION = 10 ** 18;

    mapping(address => uint256) public pendingRewardRate;
    mapping(address => bool) public isStarted;
    mapping(address => uint256) public rewardRate;
    mapping(address => uint256) public periodFinish;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => uint256) public rewardPerTokenStored;
    mapping(address => mapping(address => uint256)) public storedRewardsPerUser;

    mapping(address => mapping(address => uint256))
        public userRewardPerTokenStored;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    address[] public rewards;
    mapping(address => bool) public isReward;

    uint256 internal _unlocked;

    event Deposit(address indexed from, uint256 amount);
    event Withdraw(address indexed from, uint256 amount);
    event NotifyReward(
        address indexed from,
        address indexed reward,
        uint256 amount
    );
    event ClaimRewards(
        address indexed from,
        address indexed reward,
        uint256 amount
    );

    struct RewardInfo {
      address towerPool;
      address rewardTokenAddress;
      string rewardTokenSymbol;
      uint256 rewardTokenDecimals;
      uint256 periodFinish;
      uint256 rewardRate;
      uint256 lastUpdateTime;
      uint256 rewardPerTokenStored;
      uint256 pendingReward;
      uint256 reinvestBounty;
      bool isStarted;
    }

    function _initialize(
        address _stake,
        address[] memory _allowedRewardTokens
    ) external {
        require(factory == address(0), "TowerPool: FACTORY_ALREADY_SET");
        factory = msg.sender;
        stake = _stake;

        for (uint256 i; i < _allowedRewardTokens.length; ++i) {
            if (_allowedRewardTokens[i] != address(0)) {
                rewards.push(_allowedRewardTokens[i]);
                isReward[_allowedRewardTokens[i]] = true;
            }
        }

        _unlocked = 1;
    }

    // simple re-entrancy check
    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    function rewardsListLength() external view returns (uint256) {
        return rewards.length;
    }

    // returns the last time the reward was modified or periodFinish if the reward has ended
    function lastTimeRewardApplicable(
        address token
    ) public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish[token]);
    }

    function earned(address account) external view returns (uint256[] memory earnedList) {
        uint256 len = rewards.length;
        earnedList = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            earnedList[i] = earned(rewards[i], account);
        }
    }

    function earned(
        address token,
        address account
    ) public view returns (uint256) {
        return
            (balanceOf[account] *
                (rewardPerToken(token) -
                    userRewardPerTokenStored[account][token])) /
            PRECISION +
            storedRewardsPerUser[account][token];
    }

    // Only the tokens you claim will get updated.
    function getReward(address account, address[] memory tokens) public lock {
        require(msg.sender == account || msg.sender == factory);

        // update all user rewards regardless of tokens they are claiming
        address[] memory _rewards = rewards;
        uint256 len = _rewards.length;
        for (uint256 i; i < len; ++i) {
            if (isReward[_rewards[i]]) {
                if (!isStarted[_rewards[i]]) {
                    initializeRewardsDistribution(_rewards[i]);
                }
                updateRewardPerToken(_rewards[i], account);
            }
        }
        // transfer only the rewards they are claiming
        len = tokens.length;
        for (uint256 i; i < len; ++i){
            uint256 _reward = storedRewardsPerUser[account][tokens[i]];
            if (_reward > 0) {
                storedRewardsPerUser[account][tokens[i]] = 0;
                _safeTransfer(tokens[i], account, _reward);
                emit ClaimRewards(account, tokens[i], _reward);
            }        
        }
    }

    function rewardPerToken(address token) public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored[token];
        }
        return
            rewardPerTokenStored[token] +
            (((lastTimeRewardApplicable(token) -
                Math.min(lastUpdateTime[token], periodFinish[token])) *
                rewardRate[token] *
                PRECISION) / totalSupply);
    }

    function depositAll() external {
        deposit(IERC20(stake).balanceOf(msg.sender));
    }

    function deposit(uint256 amount) public lock {
        require(amount > 0);

        address[] memory _rewards = rewards;
        uint256 len = _rewards.length;

        for (uint256 i; i < len; ++i) {
            if (!isStarted[_rewards[i]]) {
                initializeRewardsDistribution(_rewards[i]);
            }
            updateRewardPerToken(_rewards[i], msg.sender);
        }

        _safeTransferFrom(stake, msg.sender, address(this), amount);
        totalSupply += amount;
        balanceOf[msg.sender] += amount;

        ITowerPoolFactory(factory).emitDeposit(msg.sender, amount);
        emit Deposit(msg.sender, amount);
    }

    function withdrawAll() external {
        withdraw(balanceOf[msg.sender]);
    }

    function withdraw(uint256 amount) public lock {
        require(amount > 0);

        address[] memory _rewards = rewards;
        uint256 len = _rewards.length;

        for (uint256 i; i < len; ++i) {
            updateRewardPerToken(_rewards[i], msg.sender);
        }

        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        _safeTransfer(stake, msg.sender, amount);

        ITowerPoolFactory(factory).emitWithdraw(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function left(address token) external view returns (uint256) {
        if (block.timestamp >= periodFinish[token]) return 0;
        uint256 _remaining = periodFinish[token] - block.timestamp;
        return _remaining * rewardRate[token];
    }

    // @dev rewardRate and periodFinish is set on first deposit if totalSupply == 0 or first interaction after whitelisting.
    function notifyRewardAmount(address token, uint256 amount) external lock {
        require(token != stake);
        require(amount > 0);
        rewardPerTokenStored[token] = rewardPerToken(token);
        
        // Check actual amount transferred for compatibility with fee on transfer tokens.
        uint balanceBefore = IERC20(token).balanceOf(address(this));
        _safeTransferFrom(token, msg.sender, address(this), amount);
        uint balanceAfter = IERC20(token).balanceOf(address(this));
        amount = balanceAfter - balanceBefore;
        uint _rewardRate = amount / DURATION;

        if (isStarted[token]) {
            if (block.timestamp >= periodFinish[token]) {
                rewardRate[token] = _rewardRate;
            } else {
                uint256 _remaining = periodFinish[token] - block.timestamp;
                uint256 _left = _remaining * rewardRate[token];
                require(amount > _left);
                rewardRate[token] = (amount + _left) / DURATION;
            }
            periodFinish[token] = block.timestamp + DURATION;
            lastUpdateTime[token] = block.timestamp;
        } else {
            if (pendingRewardRate[token] > 0) {
                uint256 _left = DURATION * pendingRewardRate[token];
                pendingRewardRate[token] = (amount + _left) / DURATION;
            } else {
                pendingRewardRate[token] = _rewardRate;
            }
        }
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(
            rewardRate[token] <= balance / DURATION,
            "Provided reward too high"
        );
        if (!isStarted[token]) {
            require(
                pendingRewardRate[token] <= balance / DURATION,
                "Provided reward too high"
            );
        }

        emit NotifyReward(msg.sender, token, amount);
    }

    function initializeRewardsDistribution(address token) internal {
        isStarted[token] = true;
        rewardRate[token] = pendingRewardRate[token];
        lastUpdateTime[token] = block.timestamp;
        periodFinish[token] = block.timestamp + DURATION;
        pendingRewardRate[token] = 0;
    }

    function whitelistNotifiedRewards(address token) external {
        require(msg.sender == factory);
        if (!isReward[token]) {
            isReward[token] = true;
            rewards.push(token);
        }
        if (!isStarted[token] && totalSupply > 0) {
            initializeRewardsDistribution(token);
        }
    }

    function getRewardTokenIndex(address token) public view returns (uint256) {
        address[] memory _rewards = rewards;
        uint256 len = _rewards.length;

        for (uint256 i; i < len; ++i) {
            if (_rewards[i] == token) {
                return i;
            }
        }
        return 0;
    }

    function removeRewardWhitelist(address token) external {
        require(msg.sender == factory);
        if (!isReward[token]) {
            return;
        }
        isReward[token] = false;
        uint256 idx = getRewardTokenIndex(token);
        uint256 len = rewards.length;
        for (uint256 i = idx; i < len - 1; ++i) {
            rewards[i] = rewards[i + 1];
        }
        rewards.pop();
    }

    function poke(address account) external {
        // Update reward rates and user rewards
        for (uint256 i; i < rewards.length; ++i) {
            updateRewardPerToken(rewards[i], account);
        }
    }

    function updateRewardPerToken(address token, address account) internal {
        rewardPerTokenStored[token] = rewardPerToken(token);
        lastUpdateTime[token] = lastTimeRewardApplicable(token);
        storedRewardsPerUser[account][token] = earned(token, account);
        userRewardPerTokenStored[account][token] = rewardPerTokenStored[token];
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                value
            )
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeApprove(
        address token,
        address spender,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function removeExtraRewardToken(
        uint256 index,
        uint256 duplicateIndex
    ) external onlyFactoryOwner {
        require(index < duplicateIndex);
        require(rewards[index] == rewards[duplicateIndex]);

        uint len = rewards.length;
        for (uint i = duplicateIndex; i < len - 1; ++i) {
            rewards[i] = rewards[i + 1];
        }
        rewards.pop();
    }

    function getRewardInfoList() external view returns (RewardInfo[] memory rewardInfoList) {
        uint256 len = rewards.length;
        rewardInfoList = new RewardInfo[](len);

        for (uint256 i = 0; i < len; i++) {
            address rewardToken = rewards[i];
            RewardInfo memory rewardInfo = rewardInfoList[i];
            rewardInfo.towerPool = address(this);
            rewardInfo.rewardTokenAddress = rewardToken;
            rewardInfo.rewardTokenSymbol = IERC20(rewardToken).symbol();
            rewardInfo.rewardTokenDecimals = IERC20(rewardToken).decimals();
            rewardInfo.isStarted = isStarted[rewardToken];
            rewardInfo.rewardRate = rewardRate[rewardToken];
            rewardInfo.lastUpdateTime = lastUpdateTime[rewardToken];
            rewardInfo.periodFinish = periodFinish[rewardToken];
            rewardInfo.rewardPerTokenStored = rewardPerTokenStored[rewardToken];
        }
    }

    modifier onlyFactoryOwner() {
        require(Ownable(factory).owner() == msg.sender, "NOT_AUTHORIZED");
        _;
    }
}

