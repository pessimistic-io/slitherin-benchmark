// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./IStakingPool.sol";
import "./ITipping.sol";

/// @title A pool allowing users to earn rewards for staking
contract StakingPool is Ownable, IStakingPool {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Stores user's lock amount and reward debt
    struct UserInfo {
        uint256 amount;
        uint256 lastReward;
    }

    /// @notice The {Odeum} token
    IERC20Upgradeable public odeum;
    /// @notice The {Tipping} contract
    ITipping public tipping;

    uint256 public constant PRECISION = 1e12;

    /// @notice Stores information about all user's locks and rewards
    mapping(address => UserInfo) public userInfo;
    /// @notice The amount of tokens paid to each user for his share of locked tokens
    uint256 public odeumPerShare;
    /// @notice The total amount of tokens locked in the pool
    uint256 public totalStake;
    /// @notice The list of stakers
    EnumerableSet.AddressSet private _stakers;
    /// @notice The amount of rewards claimed by each user
    mapping(address => uint256) public claimedRewards;
    /// @notice The total amount of rewards claimed by all users
    uint256 public totalClaimed;
    /// @notice Reward that were sent when there were no stakers in the contract
    /// waiting to be distributed
    uint256 public rewardAcc;

    /// @dev Only allows the {Tipping} contract to call the function
    modifier onlyTipping() {
        require(
            msg.sender == address(tipping),
            "Staking: Caller is not Tipping!"
        );
        _;
    }

    /// @dev Each user should only be able to claim his reward once after
    ///      call of `supplyReward` function. His share increases in that case.
    ///      and a new reward is different from the previous one. The difference can
    ///      be claimed. And right after that the `lastReward` should become equal
    ///      to the claimed one. So next time difference equals 0 and there is nothing
    ///      to claim.
    modifier updateLastReward() {
        _;
        UserInfo storage user = userInfo[msg.sender];
        user.lastReward = (user.amount * odeumPerShare) / PRECISION;
    }

    /// @dev Transfers all pending rewards to the caller
    modifier claimPending() {
        // Calculate the pending reward
        uint256 pending = _getPendingReward(userInfo[msg.sender]);
        // If any reward is pending, transfer it to the user
        if (pending > 0) {
            claimedRewards[msg.sender] += pending;
            totalClaimed += pending;
            odeum.safeTransfer(msg.sender, pending);
        }
        _;
    }

    constructor(address odeum_) {
        odeum = IERC20Upgradeable(odeum_);
    }

    /// @notice See {IStakingPool-getAvailableReward}
    function getAvailableReward(address user) external view returns (uint256) {
        require(user != address(0), "Staking: Invalid user address!");
        return _getPendingReward(userInfo[user]);
    }

    /// @notice See {IStakingPool-getStake}
    function getStake(address user) external view returns (uint256) {
        require(user != address(0), "Staking: Invalid user address!");
        return userInfo[user].amount;
    }

    /// @notice See {IStakingPool-getStakers}
    function getStakersCount() external view returns (uint256) {
        return _stakers.length();
    }

    /// @notice See {IStakingPool-setTipping}
    function setTipping(address tipping_) external onlyOwner {
        require(tipping_ != address(0), "Staking: Invalid tipping address!");
        tipping = ITipping(tipping_);
        emit TippingAddressChanged(tipping_);
    }

    /// @notice See {IStakingPool-deposit}
    function deposit(uint256 amount) external claimPending updateLastReward {
        UserInfo storage user = userInfo[msg.sender];
        // Calling this function with 0 amount is allowed to run modifiers
        if (amount > 0) {
            odeum.safeTransferFrom(msg.sender, address(this), amount);
            user.amount += amount;
            totalStake += amount;
            _stakers.add(msg.sender);
        }
        emit Deposit(msg.sender, amount);
    }

    /// @notice See {IStakingPool-withdraw}
    function withdraw(uint256 amount) external claimPending updateLastReward {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= amount, "Staking: Too high withdraw amount!");
        if (amount > 0) {
            user.amount -= amount;
            if (user.amount == 0) {
                _stakers.remove(msg.sender);
            }
            totalStake -= amount;
            odeum.safeTransfer(msg.sender, amount);
        }
        emit Withdraw(msg.sender, amount);
    }

    /// @notice See {IStakingPool-claim}
    function claim() external claimPending updateLastReward {
        // All claiming is done in the `claimPending` modifier.
        // Just need to get the reward here for the event
        UserInfo storage user = userInfo[msg.sender];
        uint256 pending = _getPendingReward(user);

        emit Claim(msg.sender, pending);
    }

    /// @notice See {IStakingPool-emergencyWithdraw}
    function emergencyWithdraw() external {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        _stakers.remove(msg.sender);
        user.lastReward = 0;
        totalStake -= amount;
        odeum.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, amount);
    }

    /// @notice See {IStakingPool-supplyReward}
    function supplyReward(uint256 reward) external onlyTipping {
        // Reward per share is only updated if there is at least one staker
        // save reward for a further use
        if (totalStake == 0) {
            rewardAcc += reward;
            return;
        }
        odeumPerShare = odeumPerShare + ((reward + rewardAcc) * PRECISION) / totalStake;
        delete rewardAcc;
    }

    /// @dev Returns the pending reward of the user
    /// @param user The address of the user to get the reward of
    /// @return The pending reward of the user
    function _getPendingReward(
        UserInfo storage user
    ) internal view returns (uint256) {
        // This function returns not 0 only once after `odeumPerShare` was update via `supplyReward`
        // In all other cases it returns 0. So repeated attemps to claim reward several times after
        // a single update of `odeumPerShare` will fail as reward will be 0
        return (user.amount * odeumPerShare) / PRECISION - user.lastReward;
    }
}

