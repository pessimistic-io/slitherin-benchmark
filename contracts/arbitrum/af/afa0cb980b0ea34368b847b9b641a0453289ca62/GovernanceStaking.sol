// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./IterableMappingBool.sol";
import "./IGovernanceStaking.sol";
import "./IERC20.sol";
import "./Ownable.sol";

contract GovernanceStaking is Ownable, IGovernanceStaking {

    using IterableMappingBool for IterableMappingBool.Map;

    uint256 public constant MAX_LOCK_PERIOD = 31_536_000; // 1 year

    IERC20 public token;

    uint256 public totalStaked;
    mapping(address => uint256) public userStaked;
    mapping(address => uint256) public lockEnd;
    mapping(address => mapping(address => uint256)) public userPaid; // user => token => amount
    mapping(address => uint256) public accRewardsPerToken;
    IterableMappingBool.Map private rewardTokens;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardDistributed(address token, uint256 amount);
    event TokenWhitelisted(address token);

    constructor(IERC20 _token) {
        token = _token;
    }

    /**
     *  @notice Allows a user to stake a specified amount of tokens
     *  @param _amount The amount of tokens to be staked
     *  @param _duration The duration for which tokens will be staked
     */
    function stake(uint256 _amount, uint256 _duration) external {
        token.transferFrom(msg.sender, address(this), _amount);
        _claim(msg.sender);
        userStaked[msg.sender] += _amount;
        totalStaked = totalStaked + _amount;
        if (_duration != 0) {
            uint256 oldLockEnd = lockEnd[msg.sender];
            uint256 newLockEnd = oldLockEnd == 0 ? block.timestamp + _duration : oldLockEnd += _duration;
            require(newLockEnd <= block.timestamp + MAX_LOCK_PERIOD, "Lock period too long");
            lockEnd[msg.sender] = newLockEnd;
        }
        _updateUserPaid(msg.sender);
        emit Staked(msg.sender, _amount);
    }

    /**
     *  @notice Allows a user to unstake a specified amount of tokens
     *  @param _amount The amount of tokens to be unstaked
     */
    function unstake(uint256 _amount) external {
        require(block.timestamp >= lockEnd[msg.sender], "Locked");
        _claim(msg.sender);
        userStaked[msg.sender] -= _amount;
        totalStaked = totalStaked - _amount;
        _updateUserPaid(msg.sender);
        token.transfer(msg.sender, _amount);
        emit Unstaked(msg.sender, _amount);
    }

    /**
     * @notice Allows a user to claim their rewards
     */
    function claim() external {
        _claim(msg.sender);
    }

    /**
     * @notice Distribute rewards to stakers
     * @param _token The address of the token to be distributed
     * @param _amount The amount of tokens to be distributed
     */
    function distribute(address _token, uint256 _amount) external {
        if (rewardTokens.size() == 0 || totalStaked == 0 || !rewardTokens.get(_token)) return;
        try IERC20(_token).transferFrom(msg.sender, address(this), _amount) {
            accRewardsPerToken[_token] += _amount*1e18/totalStaked;
            emit RewardDistributed(_token, _amount);
        } catch {
            return;
        }
    }

    /**
     * @notice Owner can whitelist a new token
     * @param _rewardToken The token address to be whitelisted
     */
    function whitelistReward(address _rewardToken) external onlyOwner {
        require(!rewardTokens.get(_rewardToken), "Already whitelisted");
        rewardTokens.set(_rewardToken);
        emit TokenWhitelisted(_rewardToken);
    }

    /**
     * @dev Logic for claiming rewards
     * @param _user The address that claims the rewards
     */
    function _claim(address _user) internal {
        address[] memory _tokens = rewardTokens.keys;
        uint256 _len = _tokens.length;
        for (uint256 i=0; i<_len; i++) {
            address _token = _tokens[i];
            uint256 _pending = pending(_user, _token);
            if (_pending != 0) {
                userPaid[_user][_token] += _pending;
                IERC20(_token).transfer(_user, _pending);
                emit RewardClaimed(_user, _pending);
            }
        }
    }

    /**
     * @dev Logic for updating userPaid variable for pending calculations
     * @param _user The address whose userPaid value is updated
     */
    function _updateUserPaid(address _user) internal {
        address[] memory _tokens = rewardTokens.keys;
        uint256 _len = _tokens.length;
        for (uint256 i=0; i<_len; i++) {
            address _token = _tokens[i];
            userPaid[_user][_token] = userStaked[_user] * accRewardsPerToken[_token] / 1e18;
        }
    }

    /**
     * @notice Check pending token rewards for an address
     * @param _user The address whose pending rewards are read
     * @param _token The address of the reward token
     * @return Pending token reward amount
     */
    function pending(address _user, address _token) public view returns (uint256) {
        return userStaked[_user]*accRewardsPerToken[_token]/1e18 - userPaid[_user][_token]; 
    }

    /**
     * @notice View the staked amount of an address increased by the lock duration for governance use
     * @param _user The address of whose stake is read
     * @return Weighted stake amount
     */
    function weightedStake(address _user) public view returns (uint256) {
        uint256 _compareTimestamp = block.timestamp > lockEnd[_user] ? block.timestamp : lockEnd[_user];
        return userStaked[_user] + userStaked[_user] * (_compareTimestamp - block.timestamp) / MAX_LOCK_PERIOD;
    }

}
