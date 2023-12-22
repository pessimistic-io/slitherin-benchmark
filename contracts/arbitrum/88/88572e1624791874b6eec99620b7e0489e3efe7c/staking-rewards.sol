// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;
import "./Context.sol";
import "./Math.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./Address.sol";
import "./SafeERC20.sol";

//modified from https://github.com/Uniswap/liquidity-staker/blob/master/contracts/StakingRewards.sol
contract StakingRewards is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    address public rewardsToken;
    address public stakingToken;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _rewardsToken, address _stakingToken) {
        rewardsToken = _rewardsToken;
        stakingToken = _stakingToken;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(_totalSupply)
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            _balances[account]
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        updateReward(msg.sender);
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        IERC20(stakingToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        updateReward(msg.sender);
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        IERC20(stakingToken).safeTransfer(msg.sender, amount);
    }

    function getReward() external nonReentrant {
        updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            IERC20(rewardsToken).safeTransfer(msg.sender, reward);
        }
    }

    // this function replaces the notifyRewardAmount in the Uniswap contract
    // and lets anyone call it, provided there is sufficent balance in the contract
    // also allows for resetting the rewards duration
    function startRewards(uint256 reward, uint256 newRewardDuration) external {
        require(reward > 0, "reward too small");
        require(newRewardDuration > 0, "reward duration too small");
        require(block.timestamp >= periodFinish, "rewards still in progress");
        //handle case where rewardToken is the stakingToken by stopping
        //rewards if the contract balance is less than the total amount staked
        if (rewardsToken == stakingToken) {
            require(IERC20(rewardsToken).balanceOf(address(this)).sub(_totalSupply) >= reward, "INSUFFICIENT REWARDS");
        }

        updateReward(address(0));
        rewardsDuration = newRewardDuration;
        rewardRate = reward.div(rewardsDuration);

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = IERC20(rewardsToken).balanceOf(address(this));
        require(
            rewardRate <= balance.div(rewardsDuration),
            "INSUFFICIENT REWARDS"
        );

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
    }

    function updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }
}

