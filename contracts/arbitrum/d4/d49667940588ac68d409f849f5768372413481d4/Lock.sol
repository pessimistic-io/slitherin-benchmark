// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;
pragma abicoder v2;

import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";
import {IHypervisor} from "./IHypervisor.sol";
/// @title Multi Fee Distribution Contract
/// @author Gamma
/// @dev All function calls are currently implemented without side effects
import {console} from "./console.sol";

contract MultiFeeDistribution is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;

    struct RewardData {
        uint256 amount;
        uint256 lastTimeUpdated;
        uint256 rewardPerToken;
    }

    struct UserData {
        uint256 tokenAmount;
        uint256 lastTimeUpdated;
        uint256 rewardPerToken;
        uint256 tokenClaimable;
    }
    /********************** Contract Addresses ***********************/

    /// @notice Address of LP token
    address public stakingToken;

    /********************** Lock & Earn Info ***********************/

    /// @notice Total locked value
    uint256 public totalStakes;

    /********************** Reward Info ***********************/

    /// @notice Reward tokens being distributed
    address[] public rewardTokens;

    /// @notice address => RPT
    mapping(address => RewardData) public rewardData;

    /// @notice address => RPT
    mapping(address => UserData) public userData;

    /// @notice rewardToken => user => claimable amount
    mapping(address => mapping(address => uint256)) public claimable;
    /********************** Other Info ***********************/

    /// @notice treasury wallet
    address public hypervisor;

    /// @notice Addresses approved to call mint
    mapping(address => bool) public managers;

    /********************** Events ***********************/

    event Stake(
        address indexed user,
        uint256 amount
    );
    event Unstake(
        address indexed user,
        uint256 receivedAmount
    );
    event RewardPaid(
        address indexed user,
        address indexed rewardToken,
        uint256 reward
    );
    event Recovered(address indexed token, uint256 amount);

    /********************** Errors ***********************/
    error AddressZero();
    error InvalidBurn();
    error InsufficientPermission();
    error ActiveReward();
    error InvalidAmount();

    /**
     * @dev Constructor
     */
    function initialize(
        address[] memory _rewardTokens
    ) public initializer {
        for (uint i; i < _rewardTokens.length; i ++) {
            if (_rewardTokens[i] == address(0)) revert InvalidBurn();
            rewardTokens.push(_rewardTokens[i]);
        }

        __Pausable_init();
        __Ownable_init();
    }

    /********************** Setters ***********************/

    /**
     * @notice Set managers
     * @param _managers array of address
     */
    function setManagers(address[] calldata _managers) external onlyOwner {
        uint256 length = _managers.length;
        for (uint256 i; i < length; i ++) {
            if (_managers[i] == address(0)) revert AddressZero();
            managers[_managers[i]] = true;
        }
    }

    /**
     * @notice Remove managers
     * @param _managers array of address
     */
    function removeManagers(address[] calldata _managers) external onlyOwner {
        uint256 length = _managers.length;
        for (uint256 i; i < length; i ++) {
            if (_managers[i] == address(0)) revert AddressZero();
            managers[_managers[i]] = false;
        }
    }

    /**
     * @notice Set LP token.
     * @param _stakingToken LP token address
     */
    function setStakingToken(address _stakingToken) external onlyOwner {
        if (_stakingToken == address(0)) revert AddressZero();
        if (stakingToken != address(0)) revert AddressZero();
        stakingToken = _stakingToken;
    }

    /**
     * @notice set hypervisor address
     * @param _hypervisor address of hypervisor
     */
    function setHypervisor(address _hypervisor) external onlyOwner {
        hypervisor = _hypervisor;
    }

    /**
     * @notice Add a new reward token to be distributed to stakers.
     * @param _rewardToken address
     */
    function addReward(address _rewardToken) external {
        if (_rewardToken == address(0)) revert InvalidBurn();
        if (!managers[msg.sender]) revert InsufficientPermission();
        rewardTokens.push(_rewardToken);
    }

    /********************** View functions ***********************/

    /**
     * @notice Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders.
     * @param tokenAddress to recover.
     * @param tokenAmount to recover.
     */
    function recoverERC20(
        address tokenAddress,
        uint256 tokenAmount
    ) external onlyOwner {
        if (rewardData[tokenAddress].amount > 0) revert ActiveReward();
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /**
     * @notice Total balance of an account, including unlocked, locked and earned tokens.
     * @param user address.
     */
    function totalBalance(
        address user
    ) external view returns (uint256) {
        return userData[user].tokenAmount;
    }
    
    /********************** Reward functions ***********************/

    /**
     * @notice Address and claimable amount of all reward tokens for the given account.
     * @param account for rewards
     * @return rewardsData array of rewards
     */
    function claimableRewards(
        address account
    )
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256[] memory rewardAmounts = new uint256[](rewardTokens.length);
        for (uint256 i; i < rewardTokens.length; i ++) {
            rewardAmounts[i] = claimable[rewardTokens[i]][account] + _earned(
                account,
                rewardTokens[i]
            ) / 1e50;
        }
        return (rewardTokens, rewardAmounts);
    }

    /********************** Operate functions ***********************/

    /**
     * @notice Stake tokens to receive rewards.
     * @dev Locked tokens cannot be withdrawn for defaultLockDuration and are eligible to receive rewards.
     * @param amount to stake.
     * @param onBehalfOf address for staking.
     */
    function stake(
        uint256 amount,
        address onBehalfOf
    ) external {
        _stake(amount, onBehalfOf);
    }

    /**
     * @notice Stake tokens to receive rewards.
     * @dev Locked tokens cannot be withdrawn for defaultLockDuration and are eligible to receive rewards.
     * @param amount to stake.
     * @param onBehalfOf address for staking.
     */
    function _stake(
        uint256 amount,
        address onBehalfOf
    ) internal whenNotPaused {
        if (amount == 0) return;
        for (uint i; i < rewardTokens.length; i ++) {
            _calculateClaimable(onBehalfOf, rewardTokens[i]);
        }
        IERC20(stakingToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        UserData storage data = userData[onBehalfOf];
        data.tokenAmount += amount;
        totalStakes += amount;

        _updateReward();
        emit Stake(onBehalfOf, amount);
    }

    function unstake(uint256 amount) external {
        _unstake(amount, msg.sender);
    }

    function _unstake(uint256 amount, address onBehalfOf) internal {
        UserData storage userInfo = userData[onBehalfOf];
        if (userInfo.tokenAmount < amount)
            revert InvalidAmount();
        _updateReward();
        console.log(userInfo.rewardPerToken);
        for (uint i; i < rewardTokens.length; i ++) {
            _calculateClaimable(onBehalfOf, rewardTokens[i]);
        }
        IERC20(stakingToken).safeTransfer(onBehalfOf, amount);

        userInfo.tokenAmount -= amount;
        totalStakes -= amount;

        emit Unstake(onBehalfOf, amount);
    }
    /**
     * @notice Claim all pending staking rewards.
     * @param _rewardTokens array of reward tokens
     */
    function getReward(address _onBehalfOf, address[] memory _rewardTokens) external {
        _getReward(_onBehalfOf, _rewardTokens);
    }

    /**
     * @notice Claim all pending staking rewards.
     */
    function getAllRewards() external {
        _getReward(msg.sender, rewardTokens);
    }

    /**
     * @notice Calculate rewards.
     */
    function notifyUnseenReward() external {
        for (uint256 i; i < rewardTokens.length; i ++) {
            _notifyUnseenReward(rewardTokens[i]);
        }
    }

    function updateReward() external {
        _updateReward();
    }

    /**
     * @notice Calculate earnings.
     * @param _user address of earning owner
     * @param _rewardToken address
     * @return earnings amount
     */
    function _earned(
        address _user,
        address _rewardToken
    ) internal view returns (uint256 earnings) {
        RewardData memory rewardInfo = rewardData[_rewardToken];
        UserData memory userInfo = userData[_user];
    
        return (rewardInfo.rewardPerToken - userInfo.rewardPerToken) * userInfo.tokenAmount;
    }

    /**
     * @notice Update user reward info.
     */
    function _updateReward() internal {
        IHypervisor(hypervisor).getReward();
        for (uint256 i = 0; i < rewardTokens.length; i ++) {
            address rewardToken = rewardTokens[i];
            _notifyUnseenReward(rewardToken);
        }
    }

    function _calculateClaimable(address _onBehalf, address _rewardToken) internal {
        for (uint256 i = 0; i < rewardTokens.length; i ++) {
            UserData storage userInfo = userData[_onBehalf];
            RewardData storage r = rewardData[_rewardToken];
            
            console.log('rpt', r.rewardPerToken, userInfo.rewardPerToken);
            if (userInfo.lastTimeUpdated > 0 && userInfo.tokenAmount > 0) {
                claimable[_rewardToken][_onBehalf] += (r.rewardPerToken - userInfo.rewardPerToken) * userInfo.tokenAmount / 1e50;
            }
            
            userInfo.rewardPerToken = r.rewardPerToken;
            userInfo.lastTimeUpdated = block.timestamp;            
        }

    }

    /**
     * @notice Add new reward.
     * @dev If prev reward period is not done, then it resets `rewardPerSecond` and restarts period
     * @param _rewardToken address
     */
    function _notifyUnseenReward(address _rewardToken) internal {
        if (totalStakes > 0) {
            RewardData storage r = rewardData[_rewardToken];
            uint256 diff = IERC20(_rewardToken).balanceOf(address(this)) - r.amount;
            r.lastTimeUpdated = block.timestamp;
            r.rewardPerToken += diff * 1e50 / totalStakes; 
            r.amount += diff;
        }
    }

    /**
     * @notice User gets reward
     * @param _user address
     * @param _rewardTokens array of reward tokens
     */
    function _getReward(
        address _user,
        address[] memory _rewardTokens
    ) internal whenNotPaused {
        uint256 length = _rewardTokens.length;
        for (uint256 i; i < length; i ++) {
            address token = _rewardTokens[i];
            _updateReward();
            _calculateClaimable(_user, token);
            if (claimable[token][_user] > 0) {
                IERC20(token).safeTransfer(_user, claimable[token][_user]);
                claimable[token][_user] = 0;
                emit RewardPaid(_user, token, claimable[token][_user]);
            }
        }
    }

    /********************** Eligibility + Disqualification ***********************/

    /**
     * @notice Pause MFD functionalities
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Resume MFD functionalities
     */
    function unpause() public onlyOwner {
        _unpause();
    }
}

