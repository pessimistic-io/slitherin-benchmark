// SPDX-License-Identifier: GPL-3.0-or-later

/*
 //======================================================================\\
 //======================================================================\\
    *******         **********     ***********     *****     ***********
    *      *        *              *                 *       *
    *        *      *              *                 *       *
    *         *     *              *                 *       *
    *         *     *              *                 *       *
    *         *     **********     *       *****     *       ***********
    *         *     *              *         *       *                 *
    *         *     *              *         *       *                 *
    *        *      *              *         *       *                 *
    *      *        *              *         *       *                 *
    *******         **********     ***********     *****     ***********
 \\======================================================================//
 \\======================================================================//
*/

pragma solidity ^0.8.13;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./OwnableWithoutContextUpgradeable.sol";

import "./DateTime.sol";
import "./IPriorityPoolFactory.sol";

import "./WeightedFarmingPoolEventError.sol";
import "./WeightedFarmingPoolDependencies.sol";

/**
 * @notice Weighted Farming Pool
 *
 *         Weighted farming pool support multiple tokens to earn the same reward
 *         Different tokens will have different weights when calculating rewards
 *
 *
 *         Native token premiums will be transferred to this pool
 *         The distribution is in the way of "farming" but with multiple tokens
 *
 *         Different generations of PRI-LP-1-JOE-G1
 *
 *         About the scales of variables:
 *         - weight            SCALE
 *         - share             SCALE
 *         - accRewardPerShare SCALE * SCALE / SCALE = SCALE
 *         - rewardDebt        SCALE * SCALE / SCALE = SCALE
 *         So pendingReward = ((share * acc) / SCALE - debt) / SCALE
 */
contract WeightedFarmingPool is
    WeightedFarmingPoolEventError,
    OwnableWithoutContextUpgradeable,
    WeightedFarmingPoolDependencies
{
    using DateTimeLibrary for uint256;
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constants **************************************** //
    // ---------------------------------------------------------------------------------------- //

    uint256 public constant SCALE = 1e12;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Variables **************************************** //
    // ---------------------------------------------------------------------------------------- //

    uint256 public counter;

    struct PoolInfo {
        address[] tokens; // Token addresses (PRI-LP)
        uint256[] amount; // Token amounts
        uint256[] weight; // Weight for each token
        uint256 shares; // Total shares (share = amount * weight)
        address rewardToken; // Reward token address
        uint256 lastRewardTimestamp; // Last reward timestamp
        uint256 accRewardPerShare; // Accumulated reward per share (not per token)
    }
    // Pool id => Pool info
    mapping(uint256 => PoolInfo) public pools;

    // Pool id => Year => Month => Speed
    mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256)))
        public speed;

    struct UserInfo {
        uint256[] amount; // Amount of each token
        uint256 shares; // Total shares (share = amount * weight)
        uint256 rewardDebt; // Reward debt
    }
    // Pool Id => User address => User Info
    mapping(uint256 => mapping(address => UserInfo)) public users;

    // Keccak256(poolId, token) => Whether supported
    // Ensure one token not be added for multiple times
    mapping(bytes32 => bool) public supported;

    // Pool id => Token address => Token index in the tokens array
    mapping(uint256 => mapping(address => uint256)) public tokenIndex;

    // Pool id => User address => Index => Previous Weight
    mapping(uint256 => mapping(address => mapping(uint256 => uint256)))
        public preWeight;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constructor ************************************** //
    // ---------------------------------------------------------------------------------------- //

    function initialize(address _policyCenter, address _priorityPoolFactory)
        public
        initializer
    {
        if (_policyCenter == address(0) || _priorityPoolFactory == address(0)) {
            revert WeightedFarmingPool_ZeroAddress();
        }

        __Ownable_init();

        policyCenter = _policyCenter;
        priorityPoolFactory = _priorityPoolFactory;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************** Modifiers *************************************** //
    // ---------------------------------------------------------------------------------------- //

    modifier isPriorityPool() {
        require(
            IPriorityPoolFactory(priorityPoolFactory).poolRegistered(
                msg.sender
            ),
            "Only Priority Pool"
        );
        _;
    }

    modifier onlyFactory() {
        require(
            msg.sender == priorityPoolFactory,
            "Only Priority Pool Factory"
        );
        _;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ View Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Get a user's LP amount
     *
     * @param _poolId Pool id
     * @param _user   User address
     *
     * @return amounts Amount array of user's lp in each generation of lp token
     */
    function getUserLPAmount(uint256 _poolId, address _user)
        external
        view
        returns (uint256[] memory)
    {
        return users[_poolId][_user].amount;
    }

    /**
     * @notice Get pool information arrays
     *
     * @param _poolId Pool id
     *
     * @return tokens  Token addresses array
     * @return amounts Token amounts array
     * @return weights Token weights array
     */
    function getPoolArrays(uint256 _poolId)
        external
        view
        returns (
            address[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        PoolInfo storage pool = pools[_poolId];
        return (pool.tokens, pool.amount, pool.weight);
    }

    /**
     * @notice Check whether a token is supported in a certain pool
     *
     * @param _poolId Pool id
     * @param _token  PRI-LP token address
     *
     * @return isSupported Whether supported
     */
    function supportedToken(uint256 _poolId, address _token)
        public
        view
        returns (bool isSupported)
    {
        bytes32 key = keccak256(abi.encodePacked(_poolId, _token));
        return supported[key];
    }

    /**
     * @notice Pending reward
     *
     * @param _id   Pool id
     * @param _user User's address
     *
     * @return pending Pending reward in native token
     */
    function pendingReward(uint256 _id, address _user)
        external
        view
        returns (uint256 pending)
    {
        PoolInfo storage pool = pools[_id];
        UserInfo storage user = users[_id][_user];

        // accRewardPerShare has 1 * SCALE
        uint256 accReward = pool.accRewardPerShare;
        uint256 totalReward;

        uint256 currentTime = block.timestamp;
        uint256 lastRewardTime = pool.lastRewardTimestamp;

        if (user.shares > 0) {
            if (
                lastRewardTime > 0 && block.timestamp > pool.lastRewardTimestamp
            ) {
                (uint256 lastY, uint256 lastM, uint256 lastD) = lastRewardTime
                    .timestampToDate();

                (uint256 currentY, uint256 currentM, ) = currentTime
                    .timestampToDate();

                uint256 monthPassed = currentM - lastM;

                // In the same month, use current month speed
                if (monthPassed == 0) {
                    totalReward +=
                        (currentTime - lastRewardTime) *
                        speed[_id][currentY][currentM];
                }
                // Across months, use different months' speed
                else {
                    for (uint256 i; i < monthPassed + 1; ) {
                        // First month reward
                        if (i == 0) {
                            // End timestamp of the first month
                            uint256 endTimestamp = DateTimeLibrary
                                .timestampFromDateTime(
                                    lastY,
                                    lastM,
                                    lastD,
                                    23,
                                    59,
                                    59
                                );
                            totalReward +=
                                (endTimestamp - lastRewardTime) *
                                speed[_id][lastY][lastM];
                        }
                        // Last month reward
                        else if (i == monthPassed) {
                            uint256 startTimestamp = DateTimeLibrary
                                .timestampFromDateTime(
                                    lastY,
                                    lastM,
                                    1,
                                    0,
                                    0,
                                    0
                                );

                            totalReward +=
                                (currentTime - startTimestamp) *
                                speed[_id][lastY][lastM];
                        }
                        // Middle month reward
                        else {
                            uint256 daysInMonth = DateTimeLibrary
                                ._getDaysInMonth(lastY, lastM);

                            totalReward +=
                                (DateTimeLibrary.SECONDS_PER_DAY *
                                    daysInMonth) *
                                speed[_id][lastY][lastM];
                        }

                        unchecked {
                            if (++lastM > 12) {
                                ++lastY;
                                lastM = 1;
                            }

                            ++i;
                        }
                    }
                }
            }

            accReward += (totalReward * SCALE) / pool.shares;

            pending =
                ((user.shares * accReward) / SCALE - user.rewardDebt) /
                SCALE;
        }
    }

    /**
     * @notice Register a new famring pool for priority pool
     *
     * @param _rewardToken Reward token address (protocol native token)
     */
    function addPool(address _rewardToken) external onlyFactory {
        uint256 currentId = ++counter;

        PoolInfo storage pool = pools[currentId];
        pool.rewardToken = _rewardToken;

        emit PoolAdded(currentId, _rewardToken);
    }

    /**
     * @notice Register Pri-LP token
     *
     *         Called when new generation of PRI-LP tokens are deployed
     *         Only called from a priority pool
     *
     * @param _id     Pool Id
     * @param _token  Priority pool lp token address
     * @param _weight Weight of the token in the pool
     */
    function addToken(
        uint256 _id,
        address _token,
        uint256 _weight
    ) external isPriorityPool {
        bytes32 key = keccak256(abi.encodePacked(_id, _token));
        if (supported[key]) revert WeightedFarmingPool__AlreadySupported();

        // Record as supported
        supported[key] = true;

        pools[_id].tokens.push(_token);
        pools[_id].weight.push(_weight);

        uint256 index = pools[_id].tokens.length - 1;

        // Store the token index for later check
        tokenIndex[_id][_token] = index;

        emit NewTokenAdded(_id, _token, index, _weight);
    }

    /**
     * @notice Update the weight of a token in a given pool
     *
     *         Only called from a priority pool
     *
     * @param _id        Pool Id
     * @param _token     Token address
     * @param _newWeight New weight of the token in the pool
     */
    function updateWeight(
        uint256 _id,
        address _token,
        uint256 _newWeight
    ) external isPriorityPool {
        // First update the reward till now
        // Then update the index to be the new one
        updatePool(_id);

        uint256 index = _getIndex(_id, _token);

        PoolInfo storage pool = pools[_id];

        uint256 previousWeight = pool.weight[index];
        pool.weight[index] = _newWeight;

        // Update the pool's shares immediately
        // When user interaction, update each user's share first
        pool.shares -= pool.amount[index] * (previousWeight - _newWeight);

        emit PoolWeightUpdated(_id, index, _newWeight);
    }

    /**
     * @notice Update reward speed when new premium income
     *
     *         Only called from a priority pool
     *
     * @param _id       Pool id
     * @param _newSpeed New speed (SCALED)
     * @param _years    Years to be updated
     * @param _months   Months to be updated
     */
    function updateRewardSpeed(
        uint256 _id,
        uint256 _newSpeed,
        uint256[] memory _years,
        uint256[] memory _months
    ) external isPriorityPool {
        if (_years.length != _months.length)
            revert WeightedFarmingPool__WrongDateLength();

        uint256 length = _years.length;
        for (uint256 i; i < length; ) {
            speed[_id][_years[i]][_months[i]] += _newSpeed;

            unchecked {
                ++i;
            }
        }

        emit RewardSpeedUpdated(_id, _newSpeed, _years, _months);
    }

    /**
     * @notice Deposit from Policy Center
     *
     *         No need for approval
     *         Only called from policy center
     *
     * @param _id     Pool id
     * @param _token  PRI-LP token address
     * @param _amount Amount to deposit
     * @param _user   User address
     */
    function depositFromPolicyCenter(
        uint256 _id,
        address _token,
        uint256 _amount,
        address _user
    ) external {
        if (msg.sender != policyCenter)
            revert WeightedFarmingPool__OnlyPolicyCenter();

        _deposit(_id, _token, _amount, _user);
    }

    /**
     * @notice Directly deposit (need approval)
     */
    function deposit(
        uint256 _id,
        address _token,
        uint256 _amount
    ) external {
        _deposit(_id, _token, _amount, msg.sender);

        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
    }

    function withdrawFromPolicyCenter(
        uint256 _id,
        address _token,
        uint256 _amount,
        address _user
    ) external {
        if (msg.sender != policyCenter)
            revert WeightedFarmingPool__OnlyPolicyCenter();

        _withdraw(_id, _token, _amount, _user);
    }

    function withdraw(
        uint256 _id,
        address _token,
        uint256 _amount
    ) external {
        _withdraw(_id, _token, _amount, msg.sender);
    }

    /**
     * @notice Deposit PRI-LP tokens
     *
     * @param _id     Farming pool id
     * @param _token  PRI-LP token address
     * @param _amount PRI-LP token amount
     * @param _user   Real user address
     */
    function _deposit(
        uint256 _id,
        address _token,
        uint256 _amount,
        address _user
    ) internal {
        if (_amount == 0) revert WeightedFarmingPool__ZeroAmount();
        if (_id > counter) revert WeightedFarmingPool__InexistentPool();

        updatePool(_id);

        uint256 index = _getIndex(_id, _token);

        _updateUserWeight(_id, _user, index);

        PoolInfo storage pool = pools[_id];
        UserInfo storage user = users[_id][_user];

        if (user.shares > 0) {
            uint256 pending = ((user.shares * pool.accRewardPerShare) /
                SCALE -
                user.rewardDebt) / SCALE;

            uint256 actualReward = _safeRewardTransfer(
                pool.rewardToken,
                _user,
                pending
            );

            emit Harvest(_id, _user, _user, actualReward);
        }

        // check if current index exists for user
        // index is 0, push
        // length <= index
        uint256 userLength = user.amount.length;
        if (userLength < index + 1) {
            // If user amount length is 0, index is 1 => Push 2 zeros
            // If user amount length is 1, index is 1 => Push 1 zero
            // If user amount length is 1, index is 2 => Push 2 zeros
            for (uint256 i = userLength; i < index + 1; ) {
                user.amount.push(0);

                unchecked {
                    ++i;
                }
            }
        }

        uint256 poolLength = pool.amount.length;
        if (poolLength < index + 1) {
            for (uint256 i = poolLength; i < index + 1; ) {
                pool.amount.push(0);

                unchecked {
                    ++i;
                }
            }
        }

        uint256 currentWeight = pool.weight[index];

        // Update user amount for this gen lp token
        user.amount[index] += _amount;
        user.shares += _amount * currentWeight;

        // Record this user's previous weight for this token index
        preWeight[_id][_user][index] = currentWeight;

        // Update pool amount for this gen lp token
        pool.amount[index] += _amount;
        pool.shares += _amount * currentWeight;

        user.rewardDebt = (user.shares * pool.accRewardPerShare) / SCALE;
    }

    /**
     * @notice Update a user's weight
     *
     * @param _id    Pool id
     * @param _user  User address
     * @param _index Token index in this pool
     */
    function _updateUserWeight(
        uint256 _id,
        address _user,
        uint256 _index
    ) internal {
        PoolInfo storage pool = pools[_id];
        UserInfo storage user = users[_id][_user];

        if (pool.weight.length > 0) {
            uint256 weight = pool.weight[_index];
            uint256 previousWeight = preWeight[_id][_user][_index];

            if (previousWeight != 0) {
                // Only update when weight changes
                if (weight != previousWeight) {
                    uint256 amount = user.amount[_index];

                    // Weight is always decreasing
                    // Ensure: previousWeight - weight > 0
                    user.shares -= amount * (previousWeight - weight);
                }
            }
        }
    }

    function _withdraw(
        uint256 _id,
        address _token,
        uint256 _amount,
        address _user
    ) internal {
        if (_amount == 0) revert WeightedFarmingPool__ZeroAmount();
        if (_id > counter) revert WeightedFarmingPool__InexistentPool();
        if (!supportedToken(_id, _token))
            revert WeightedFarmingPool__NotSupported();

        updatePool(_id);

        uint256 index = _getIndex(_id, _token);

        _updateUserWeight(_id, _user, index);

        PoolInfo storage pool = pools[_id];
        UserInfo storage user = users[_id][_user];

        if (_amount > user.amount[index])
            revert WeightedFarmingPool__NotEnoughAmount();

        if (user.shares > 0) {
            uint256 pending = ((user.shares * pool.accRewardPerShare) /
                SCALE -
                user.rewardDebt) / SCALE;

            uint256 actualReward = _safeRewardTransfer(
                pool.rewardToken,
                _user,
                pending
            );

            emit Harvest(_id, _user, _user, actualReward);
        }

        IERC20(_token).transfer(_user, _amount);

        user.amount[index] -= _amount;
        user.shares -= _amount * pool.weight[index];

        pool.amount[index] -= _amount;
        pool.shares -= _amount * pool.weight[index];

        user.rewardDebt = (user.shares * pool.accRewardPerShare) / SCALE;
    }

    function updatePool(uint256 _id) public {
        PoolInfo storage pool = pools[_id];

        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }

        if (pool.shares > 0) {
            uint256 newReward = _updateReward(_id);

            // accRewardPerShare has 1 * SCALE
            pool.accRewardPerShare += (newReward * SCALE) / pool.shares;

            pool.lastRewardTimestamp = block.timestamp;

            emit PoolUpdated(_id, pool.accRewardPerShare);
        } else {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
    }

    function harvest(uint256 _id, address _to) external {
        if (_id > counter) revert WeightedFarmingPool__InexistentPool();

        updatePool(_id);

        PoolInfo storage pool = pools[_id];
        UserInfo storage user = users[_id][msg.sender];

        if (user.shares > 0) {
            uint256 pending = ((user.shares * pool.accRewardPerShare) /
                SCALE -
                user.rewardDebt) / SCALE;

            uint256 actualReward = _safeRewardTransfer(
                pool.rewardToken,
                _to,
                pending
            );

            emit Harvest(_id, msg.sender, _to, actualReward);

            user.rewardDebt = (user.shares * pool.accRewardPerShare) / SCALE;
        }
    }

    /**
     * @notice Update reward for a pool
     *
     * @param _id Pool id
     */
    function _updateReward(uint256 _id)
        internal
        view
        returns (uint256 totalReward)
    {
        PoolInfo storage pool = pools[_id];

        uint256 currentTime = block.timestamp;
        uint256 lastRewardTime = pool.lastRewardTimestamp;

        (uint256 lastY, uint256 lastM, ) = lastRewardTime.timestampToDate();

        (uint256 currentY, uint256 currentM, ) = currentTime.timestampToDate();

        // If time goes across years
        // Change the calculation of months passed
        uint256 monthPassed;
        if (currentY > lastY) {
            monthPassed = currentM + 12 * (currentY - lastY) - lastM;
        } else {
            monthPassed = currentM - lastM;
        }

        // In the same month, use current month speed
        if (monthPassed == 0) {
            totalReward +=
                (currentTime - lastRewardTime) *
                speed[_id][currentY][currentM];
        }
        // Across months, use different months' speed
        else {
            for (uint256 i; i < monthPassed + 1; ) {
                // First month reward
                if (i == 0) {
                    uint256 daysInMonth = DateTimeLibrary._getDaysInMonth(
                        lastY,
                        lastM
                    );
                    // End timestamp of the first month
                    uint256 endTimestamp = DateTimeLibrary
                        .timestampFromDateTime(
                            lastY,
                            lastM,
                            daysInMonth,
                            23,
                            59,
                            59
                        );
                    totalReward +=
                        (endTimestamp - lastRewardTime) *
                        speed[_id][lastY][lastM];
                }
                // Last month reward
                else if (i == monthPassed) {
                    uint256 startTimestamp = DateTimeLibrary
                        .timestampFromDateTime(lastY, lastM, 1, 0, 0, 0);

                    totalReward +=
                        (currentTime - startTimestamp) *
                        speed[_id][lastY][lastM];
                }
                // Middle month reward
                else {
                    uint256 daysInMonth = DateTimeLibrary._getDaysInMonth(
                        lastY,
                        lastM
                    );

                    totalReward +=
                        (DateTimeLibrary.SECONDS_PER_DAY * daysInMonth) *
                        speed[_id][lastY][lastM];
                }

                unchecked {
                    if (++lastM > 12) {
                        ++lastY;
                        lastM = 1;
                    }

                    ++i;
                }
            }
        }
    }

    /**
     * @notice Safely transfers reward to a user address
     *
     * @param _token  Reward token address
     * @param _to     Address to send reward to
     * @param _amount Amount to send
     */
    function _safeRewardTransfer(
        address _token,
        address _to,
        uint256 _amount
    ) internal returns (uint256 actualAmount) {
        uint256 balance = IERC20(_token).balanceOf(address(this));

        if (_amount > balance) {
            actualAmount = balance;
        } else {
            actualAmount = _amount;
        }

        // Check the balance before and after the transfer
        // to check the final actual amount
        uint256 balanceBefore = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_to, actualAmount);
        uint256 balanceAfter = IERC20(_token).balanceOf(address(this));

        actualAmount = balanceBefore - balanceAfter;
    }

    /**
     * @notice Returns the index of Cover Right token given a pool id and crtoken address
     *
     *         If the token is not supported, revert with an error (to avoid return default value as 0)
     *
     * @param _id    Pool id
     * @param _token LP token address
     *
     * @return index Index of the token in the pool
     */
    function _getIndex(uint256 _id, address _token)
        internal
        view
        returns (uint256 index)
    {
        if (!supportedToken(_id, _token))
            revert WeightedFarmingPool__NotSupported();

        index = tokenIndex[_id][_token];
    }
}

