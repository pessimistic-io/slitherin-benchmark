// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.9;

import "./SafeMath.sol";
import "./Initializable.sol";
import "./ERC20.sol";
import "./Strings.sol";

import "./ReentrancyGuardUpgradeable.sol";
import "./IStakeERC20.sol";
import "./IStakeERC20Factory.sol";

contract StakeERC20 is Initializable, ReentrancyGuardUpgradeable, IStakeERC20 {
    using Strings for uint256;
    using SafeMath for uint256;

    IStakeERC20Factory public factory;

    uint256 public rewardRate = 0;

    IERC20 public stakingToken;
    IERC20 public rewardsToken;

    uint256 public lastUpdateTime;

    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;

    mapping(address => uint256) public rewards;

    uint256 public _totalSupply;

    mapping(address => uint256) public _balances;

    function setRewardRate(uint256 rate) public returns (bool) {
        rewardRate = rate;
        emit RewardAdded(rate);
        return true;
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored.add(blockTime().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply));
    }

    function blockTime() public view returns (uint256) {
        return block.timestamp;
    }

    function earned(address account) public view returns (uint256) {
        return
            _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(
                rewards[account]
            );
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = blockTime();
        if (account != address(0)) {
            // 更新奖励数量
            rewards[account] = earned(account);
            // 更新用户的累加值
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyFactory() {
        require(msg.sender == address(factory), "StakeERC20: UNAUTHORIZED");
        _;
    }

    function initialize(address factory_, address _stakingToken, address _rewardsToken) public initializer {
        __ReentrancyGuard_init();
        factory = IStakeERC20Factory(factory_);
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardsToken);
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        stakingToken.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stakingToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
}

