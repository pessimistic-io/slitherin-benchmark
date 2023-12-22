// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20_IERC20.sol";
import "./ReentrancyGuard.sol";
import "./AccessControl.sol";
import "./TransferHelper.sol";

contract Staking is AccessControl, ReentrancyGuard {
    string public constant TEST = "TEST";
    uint256 public constant PERCENT_BASE = 1e18;
    address public immutable arsh;
    address public immutable xarsh;
    uint256 public lockedAmount;
    uint256 public stakedAmount;
    uint256 public rewardAmount;
    uint256 public numOfStakers;
    uint256 public totalValueLocked;
    uint256 public depositsAmount;
    uint256 public aprSum;
    Pool[] public pools;
    mapping(address => DepositInfo[]) public addressToDepositInfo;
    mapping(address => UserInfo) public addressToUserInfo;

    uint256[6] public stakeToLevel;
    uint256[6] public levelToWeight;

    struct DepositInfo {
        uint256 amount;
        uint128 start;
        uint128 poolId;
        uint256 maxUnstakeReward;
        uint256 rewardCollected;
        uint256 depositApr;
    }

    struct UserInfo {
        uint256 totalStakedAmount;
        uint256 level;
    }

    struct Pool {
        uint128 apr;
        uint128 timeLockUp;
        uint256 commission;
    }

    event Staked(
        address indexed user,
        uint256 amount,
        uint256 start,
        uint128 poolId,
        uint256 level,
        uint256 indexed totalStaked
    );

    event Withdraw(
        address indexed user,
        uint256 amount,
        uint128 poolId,
        bool earlyWithdraw,
        uint256 level,
        uint256 indexed totalStaked
    );

    event Harvest(address user, uint256 amount);
    event WithdrawExcess(address user, uint256 amount);

    /**
     * @param _owner address of admin
     * @param  _apr = 0.07/0.25/0.7 * 1e18 / 525600
     * @param _timeLockUp = 30/90/180 * 60 * 60 * 24
     * @param _stakeToLevel amount in arsh for reaching level
     */
    constructor(
        address _owner,
        address _arsh,
        address _xarsh,
        uint128[3] memory _apr,
        uint128[3] memory _timeLockUp,
        uint256[6] memory _stakeToLevel,
        uint256[6] memory _levelToWeight
    ) {
        require(_owner != address(0), "Zero owner address");
        _setupRole(0x0, _owner);
        require(_arsh != address(0), "Zero token address");
        arsh = _arsh;
        require(_xarsh != address(0), "Zero token address");
        xarsh = _xarsh;
        for (uint256 i; i < 3; i++) {
            pools.push(Pool(_apr[i], _timeLockUp[i], 70 * 1e16));
        }
        stakeToLevel = _stakeToLevel;
        levelToWeight = _levelToWeight;
    }

    /**
     * @param _poolId index of pool in pools
     * @param _commission new commission perсent of pool mul 10^18
     */
    function setCommission(
        uint128 _poolId,
        uint256 _commission
    ) external onlyRole(0x0) {
        require(_poolId < pools.length, "Pool: wrong pool");
        require(_commission <= PERCENT_BASE, "comission > 100%");
        pools[_poolId].commission = _commission;
    }

    /**
     * @param _poolId = index of pool in pools
     * @param _apr = 0.07 * 1e18 / 525600 (example)
     */
    function setApr(uint256 _poolId, uint128 _apr) external onlyRole(0x0) {
        require(_poolId < pools.length, "Pool: wrong pool");
        pools[_poolId].apr = _apr;
    }

    /**
     * @notice allow owners to add new pool
     * @param newPool - pool struct with params
     * apr - reward perсent of pool mul 10^18 div 525600
     * timeLockUp - time of pool in seconds
     * commission - commission perсent of pool mul 10^18
     */
    function addPool(Pool calldata newPool) external onlyRole(0x0) {
        require(newPool.commission <= PERCENT_BASE, "Commission > 100%");
        pools.push(newPool);
    }

    function depositXArsh(uint256 amount) external onlyRole(0x0) {
        require(amount > 0, "Token: zero amount");
        TransferHelper.safeTransferFrom(
            xarsh,
            _msgSender(),
            address(this),
            amount
        );
        rewardAmount += amount;
    }

    /**
     * @notice Create deposit for msg.sender with input params
     * tokens must be approved for contract before call this func
     * fires Staked event
     * @param amount initial stake ARSH token amount
     * @param _poolId - id of pool of deposit,
     * = 0 for 30 days, 1 for 90 days, 2 for 180 days, 3+ for new pools
     */
    function stake(uint128 _poolId, uint256 amount) external nonReentrant {
        require(amount > 0, "Token: zero amount");
        require(_poolId < pools.length, "Pool: wrong pool");
        Pool memory pool = pools[_poolId];
        uint256 _maxUnstakeReward = ((amount * pool.apr * pool.timeLockUp) /
            1 minutes) / PERCENT_BASE;
        lockedAmount += _maxUnstakeReward;
        stakedAmount += amount;
        require(
            lockedAmount <= IERC20(xarsh).balanceOf(address(this)),
            "Token: do not have enough reward"
        );
        if (addressToDepositInfo[_msgSender()].length == 0) {
            numOfStakers++;
        }
        addressToDepositInfo[_msgSender()].push(
            DepositInfo(
                amount,
                uint128(block.timestamp),
                _poolId,
                _maxUnstakeReward,
                0,
                pool.apr
            )
        );

        // check level change
        UserInfo storage _user = addressToUserInfo[_msgSender()];
        _user.totalStakedAmount += amount;
        totalValueLocked += amount;
        depositsAmount++;
        aprSum += pool.apr;
        while (_user.level != 6) {
            if (_user.totalStakedAmount >= stakeToLevel[_user.level]) {
                _user.level++;
            } else {
                break;
            }
        }

        TransferHelper.safeTransferFrom(
            arsh,
            _msgSender(),
            address(this),
            amount
        );
        emit Staked(
            _msgSender(),
            amount,
            block.timestamp,
            _poolId,
            _user.level,
            _user.totalStakedAmount
        );
    }

    /**
     * @notice Withdraw deposit with _depositInfoId for caller,
     * allow early withdraw, fire Withdraw event
     * @param _depositInfoId - id of deposit of caller
     */
    function withdraw(uint256 _depositInfoId) external nonReentrant {
        require(
            addressToDepositInfo[_msgSender()].length > 0,
            "You dont have any deposits"
        );
        uint256 lastDepositId = addressToDepositInfo[_msgSender()].length - 1;
        require(_depositInfoId <= lastDepositId, "Deposit: wrong id");

        DepositInfo memory deposit = addressToDepositInfo[_msgSender()][
            _depositInfoId
        ];

        stakedAmount -= deposit.amount;

        uint256 reward;
        bool earlyWithdraw;
        (reward, earlyWithdraw) = getRewardAmount(_msgSender(), _depositInfoId);
        lockedAmount -= reward;
        rewardAmount -= reward;
        uint256 amount = deposit.amount;
        // sub commission
        if (earlyWithdraw) {
            Pool memory pool = pools[deposit.poolId];
            uint256 progress = 1 -
                (((block.timestamp - deposit.start) / 1 seconds) /
                    pool.timeLockUp) *
                1e16;
            amount -=
                (deposit.amount * pools[deposit.poolId].commission * progress) /
                PERCENT_BASE;
        }
        // check level change
        UserInfo storage _user = addressToUserInfo[_msgSender()];
        _user.totalStakedAmount -= deposit.amount;
        totalValueLocked -= deposit.amount;
        depositsAmount--;
        aprSum -= deposit.depositApr;
        while (_user.level != 0) {
            if (_user.totalStakedAmount < stakeToLevel[_user.level - 1]) {
                _user.level--;
            } else {
                break;
            }
        }
        if (_depositInfoId != lastDepositId) {
            addressToDepositInfo[_msgSender()][
                _depositInfoId
            ] = addressToDepositInfo[_msgSender()][lastDepositId];
        }
        addressToDepositInfo[_msgSender()].pop();
        if (lastDepositId == 0) {
            numOfStakers--;
        }

        TransferHelper.safeTransfer(arsh, _msgSender(), amount);
        TransferHelper.safeTransfer(xarsh, _msgSender(), reward);

        emit Withdraw(
            _msgSender(),
            amount,
            deposit.poolId,
            earlyWithdraw,
            _user.level,
            _user.totalStakedAmount
        );
    }

    /**
     * @notice Withdraw only accumulated reward for caller,
     * fire Harvest event
     * @param _depositInfoId - id of deposit of caller
     */
    function harvest(uint256 _depositInfoId) external nonReentrant {
        require(
            _depositInfoId < addressToDepositInfo[_msgSender()].length,
            "Pool: wrong staking id"
        );

        uint256 reward;
        (reward, ) = getRewardAmount(_msgSender(), _depositInfoId);
        require(reward > 0, "Nothing to harvest");

        addressToDepositInfo[_msgSender()][_depositInfoId]
            .rewardCollected += reward;
        _harvest(reward);
    }

    /**
     * @notice Withdraw only accumulated reward for caller
     * from all his deposits, fire Harvest event, call with caution,
     * may cost a lot of gas
     */
    function harvestAll() external nonReentrant {
        uint256 length = addressToDepositInfo[_msgSender()].length;
        require(length > 0, "Nothing to harvest");
        uint256 reward;
        uint256 totalReward;
        for (uint256 i = 0; i < length; i++) {
            (reward, ) = getRewardAmount(_msgSender(), i);
            addressToDepositInfo[_msgSender()][i].rewardCollected += reward;
            totalReward += reward;
        }
        require(totalReward > 0, "Nothing to harvest");
        _harvest(totalReward);
    }

    /**
     * @notice Withdraw excess amount of ARSH from this contract,
     * can be called only by admin,
     * excess = ARSH balance of this - (all deposits amount + max rewards),
     * fire WithdrawExcess event
     * @param amount - how many ARSH withdraw
     */
    function withdrawExcess(
        uint256 amount
    ) external onlyRole(0x0) nonReentrant {
        require(
            amount > 0 &&
                amount <= IERC20(xarsh).balanceOf(address(this)) - lockedAmount,
            "Token: not enough excess"
        );
        rewardAmount -= amount;
        TransferHelper.safeTransfer(xarsh, _msgSender(), amount);
        emit WithdrawExcess(_msgSender(), amount);
    }

    function emergencyWithdraw() external onlyRole(0x0) nonReentrant {
        uint256 amount = IERC20(xarsh).balanceOf(address(this));
        rewardAmount -= amount;
        TransferHelper.safeTransfer(xarsh, _msgSender(), amount);
        emit WithdrawExcess(_msgSender(), amount);
    }

    /**
     * @param _users array of user addresses
     * @return weights for all _users in such order
     */
    function getWeightBatch(
        address[] calldata _users
    ) external view returns (uint256[] memory) {
        uint256 length = _users.length;
        require(length > 0, "Zero length");
        uint256[] memory weigths = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            weigths[i] = getWeight(_users[i]);
        }
        return weigths;
    }

    /**
     * @param _users array of user addresses
     * @return totalStakedAmount for all _users in such order
     */
    function getTotalStakeBatch(
        address[] calldata _users
    ) external view returns (uint256[] memory) {
        uint256 length = _users.length;
        require(length > 0, "Zero length");
        uint256[] memory totalStaked = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            totalStaked[i] = addressToUserInfo[_users[i]].totalStakedAmount;
        }
        return totalStaked;
    }

    /**
     * @return total num of pools
     */
    function getPoolsAmount() external view returns (uint256) {
        return pools.length;
    }

    /**
     * @notice return reward amount of deposit with input params
     * @param _user - address of deposit holder
     * @param _depositInfoId - id of deposit of _user
     * @return reward amount = initial balance + reward - collected reward
     * @return earlyWithdraw - if early unstake = true, else = false
     */
    function getRewardAmount(
        address _user,
        uint256 _depositInfoId
    ) public view returns (uint256, bool) {
        DepositInfo memory deposit = addressToDepositInfo[_user][
            _depositInfoId
        ];
        Pool memory pool = pools[deposit.poolId];
        uint256 amount;
        bool earlyWithdraw;
        if (deposit.start + pool.timeLockUp >= block.timestamp) {
            earlyWithdraw = true;
        }
        if (earlyWithdraw) {
            amount =
                (((block.timestamp - deposit.start) / 1 minutes) *
                    deposit.amount *
                    deposit.depositApr) /
                PERCENT_BASE -
                deposit.rewardCollected;
        } else {
            amount = deposit.maxUnstakeReward - deposit.rewardCollected;
        }
        return (amount, earlyWithdraw);
    }

    /**
     * @return array where [i] element has info about deposit[i]
     * [0] - staked amount, [1] - earned, [2] - poolId,
     * [3] - commission percent * BASE, [4] - end lock timestamp
     */
    function getFront(
        address _user
    ) external view returns (uint256[5][] memory) {
        uint256 length = addressToDepositInfo[_user].length;
        uint256[5][] memory res = new uint256[5][](length);
        for (uint256 i = 0; i < length; ) {
            uint256 poolId = uint256(addressToDepositInfo[_user][i].poolId);
            (uint256 earned, ) = getRewardAmount(_user, i);
            uint256 progress = 1 -
                (((block.timestamp - addressToDepositInfo[_user][i].start) /
                    1 seconds) / pools[poolId].timeLockUp) *
                1e16;
            res[i] = [
                addressToDepositInfo[_user][i].amount,
                earned,
                poolId,
                uint256(pools[poolId].commission * progress),
                uint256(
                    addressToDepositInfo[_user][i].start +
                        pools[poolId].timeLockUp
                )
            ];
            unchecked {
                ++i;
            }
        }
        return res;
    }

    /**
     * @param _user address of user
     * @return weight of user
     */
    function getWeight(address _user) public view returns (uint256) {
        uint256 level = addressToUserInfo[_user].level;
        if (level == 0) {
            return 0;
        } else {
            return levelToWeight[level - 1];
        }
    }

    /**
     * @notice view function to get statistic information
     * @return total staked amount
     * @return sum of all existed deposits' APRs * PERCENT_BASE
     * @return current number of deposits
     */
    function getTvlAndApr() public view returns (uint256, uint256, uint256) {
        return (totalValueLocked, aprSum, depositsAmount);
    }

    /**
     * @notice called from harvest and harvestAll, fire Harvest event
     */
    function _harvest(uint256 reward) internal {
        lockedAmount -= reward;
        rewardAmount -= reward;
        TransferHelper.safeTransfer(xarsh, _msgSender(), reward);
        emit Harvest(_msgSender(), reward);
    }
}

