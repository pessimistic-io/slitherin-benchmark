// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./CoreRef.sol";

contract FarmTokenPool is Ownable, ReentrancyGuard, CoreRef {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /***************************************************** STORAGE **********************************************/

    IERC20 public rewardToken;

    address public rewardSender;

    uint256 public constant PRECISION = 1e18;

    struct User {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct Pool {
        bool isActive;
        uint256 creationTS;
        uint256 accRewardPerShare;
        uint256 totalStaked;
    }

    Pool[] public pools;

    mapping(uint256 => mapping(address => User)) public users; // trancheId => address => User

    // Events

    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 reward);
    event AdminTokenRecovery(address indexed tokenRecovered, uint256 amount);

    constructor(address _core, address _rewardToken) CoreRef(_core) {
        rewardToken = IERC20(_rewardToken);
        Pool memory pool = Pool(true, block.timestamp, 0, 0);
        pools.push(pool);
        pools.push(pool);
    }

    modifier isRewardSender() {
        require(msg.sender == address(rewardSender), "VeWTF Staking: the account is not allowed to transfer rewards");
        _;
    }

    function isPoolActive() public view returns (bool) {
        return pools[0].isActive && pools[1].isActive;
    }

    /**
     * @notice sendRewards can be used by fee collector to send fee rewards to this contract
     */

    function sendRewards(uint256 trancheId, uint256 _amount) external isRewardSender {
        require(isPoolActive(), "Pool is not active");
        bool canSend = pools[trancheId].totalStaked > 0;
        require(canSend, "Yego Finance: cannot send rewards because there are no stakes");
        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
        _updatePool(trancheId, _amount);
    }

    function stake(uint256 trancheId, address account, uint256 _amount) external nonReentrant isRewardSender {
        require(isPoolActive(), "Pool is closed");
        require(_amount > 0, "Stake amount should be positive");

        User storage user = users[trancheId][account];

        // Send pending rewards

        if (user.amount > 0) {
            uint256 reward = pools[trancheId].accRewardPerShare.mul(user.amount).div(PRECISION).sub(user.rewardDebt);
            if (reward > 0) {
                rewardToken.safeTransfer(account, reward);
            }
        }

        user.amount = user.amount.add(_amount);
        pools[trancheId].totalStaked = pools[trancheId].totalStaked.add(_amount);

        user.rewardDebt = pools[trancheId].accRewardPerShare.mul(user.amount).div(PRECISION);

        emit Stake(account, _amount);
    }

    function unstake(uint256 trancheId, address account, uint256 _amount) external nonReentrant isRewardSender {
        User storage user = users[trancheId][account];

        require(_amount > 0, "Yego Staking: cannot withdraw zero amount");
        require(_amount <= user.amount, "Yego staking: not enough tokens to withdraw");

        // Send rewards

        uint256 reward = pools[trancheId].accRewardPerShare.mul(user.amount).div(PRECISION).sub(user.rewardDebt);

        if (reward > 0) {
            rewardToken.safeTransfer(account, reward);
        }

        user.amount = user.amount.sub(_amount);
        pools[trancheId].totalStaked = pools[trancheId].totalStaked.sub(_amount);

        user.rewardDebt = pools[trancheId].accRewardPerShare.mul(user.amount).div(PRECISION);

        emit Unstake(account, _amount);
    }

    function claimRewards(uint256 trancheId) external nonReentrant {
        User storage user = users[trancheId][msg.sender];
        uint256 reward;

        if (user.amount > 0) {
            reward = pools[trancheId].accRewardPerShare.mul(user.amount).div(PRECISION).sub(user.rewardDebt);
            if (reward > 0) {
                rewardToken.safeTransfer(msg.sender, reward);
            }
        }
        user.rewardDebt = pools[trancheId].accRewardPerShare.mul(user.amount).div(PRECISION);
        emit Claim(msg.sender, reward);
    }

    function _updatePool(uint256 trancheId, uint256 _amount) internal {
        pools[trancheId].accRewardPerShare = pools[trancheId].accRewardPerShare.add(
            _amount.mul(PRECISION).div(pools[trancheId].totalStaked)
        );
    }

    /*
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingRewardOf(address _user) external view returns (uint256 reward) {
        for (uint256 i = 0; i < pools.length; i++) {
            User memory user = users[i][_user];
            reward += pools[i].accRewardPerShare.mul(user.amount).div(PRECISION).sub(user.rewardDebt);
        }
    }

    function setRewardToken(address _rewardToken) external onlyGovernor {
        require(_rewardToken != address(0), "Yego Staking: zero address");
        rewardToken = IERC20(_rewardToken);
    }

    function setRewardSender(address _rewardSender) external onlyGovernor {
        require(_rewardSender != address(0), "Yego Staking: zero address");
        rewardSender = _rewardSender;
    }

    function closePool(uint256 trancheId) external onlyGovernor {
        pools[trancheId].isActive = false;
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(address to, uint256 _amount) external onlyGovernor {
        rewardToken.safeTransfer(to, _amount);
    }

    function evacuateETH(address recv) public onlyGovernor {
        payable(recv).transfer(address(this).balance);
    }

    /*
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */

    function recoverWrongTokens(address to, address _tokenAddress, uint256 _tokenAmount) external onlyGovernor {
        require(_tokenAddress != address(rewardToken), "Yego Staking: Cannot be reward token");

        IERC20(_tokenAddress).safeTransfer(to, _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }
}

