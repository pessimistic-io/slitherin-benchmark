// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";

import "./IERC20.sol";

contract Staking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    address DEAD = 0x000000000000000000000000000000000000dEaD;

    // Whether a limit is set for users
    bool public hasUserLimit;

    // Whether it is initialized
    bool public isInitialized;

    // Accrued token per share
    uint256 public accTokenPerShare;

    // The block number when CAKE mining ends.
    uint256 public bonusEndBlock;

    // The block number when CAKE mining starts.
    uint256 public startBlock;

    // The block number of the last pool update
    uint256 public lastRewardBlock;

    // The pool limit (0 if none)
    uint256 public poolLimitPerUser;

    // CAKE tokens created per block.
    uint256 public rewardPerBlock;

    // The precision factor
    uint256 public PRECISION_FACTOR;

    // The staked token
    IERC20 public stakedToken;

    uint256 public totalStakedTokens;

    uint256 public totalRewards;

    uint256 public lockTime;

    uint256 public depositFee;

    uint256 public earlyPenalty;

    address public preSaleManager;

    IERC20 public rewardToken;

    uint256 public poolEndAt;

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => UserInfo) public userInfo;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
        uint256 stakedTime;
    }

    modifier onlyPreSaleManager() {
        require(
            msg.sender == preSaleManager,
            "Only Presale manager can call tis function"
        );
        _;
    }

    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartAndEndBlocks(uint256 startBlock, uint256 endBlock);
    event NewRewardPerBlock(uint256 rewardPerBlock);
    event NewPoolLimit(uint256 poolLimitPerUser);
    event RewardsStop(uint256 blockNumber);
    event Withdraw(address indexed user, uint256 amount);

    // constructor() public {
    //     SMART_CHEF_FACTORY = msg.sender;
    // }

    /*
     * @notice Initialize the contract
     * @param _stakedToken: staked token address
     * @param _rewardToken: reward token address
     * @param _rewardPerBlock: reward per block (in rewardToken)
     * @param _startBlock: start block
     * @param _bonusEndBlock: end block
     * @param _poolLimitPerUser: pool limit per user in stakedToken (if any, else 0)
     * @param _admin: admin address with ownership
     */

    constructor(
        IERC20 _stakedToken,
        uint256 _totalRewards,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _lockTime,
        uint256 _decimal
    ) {
        stakedToken = _stakedToken;
        rewardToken = _stakedToken;

        poolEndAt = _endTime;

        totalRewards = _totalRewards;

        uint256 _startBlock = block.number +
            ((_startTime - block.timestamp) * 12);
        uint256 _bonusEndBlock = block.number +
            ((_endTime - block.timestamp) * 12);
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        rewardPerBlock = _totalRewards / (bonusEndBlock - startBlock);

        PRECISION_FACTOR = uint256(10 ** (uint256(30).sub(_decimal)));

        // Set the lastRewardBlock as the startBlock
        lastRewardBlock = startBlock;

        lockTime = _lockTime;

        earlyPenalty = 15;
        // Transfer ownership to the admin address who becomes owner of the contract
        // transferOwnership(_admin);
    }

    /*
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function deposit(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        if (hasUserLimit) {
            require(
                _amount.add(user.amount) <= poolLimitPerUser,
                "User amount exceeds limit"
            );
        }

        _updatePool();

        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(accTokenPerShare)
                .div(PRECISION_FACTOR)
                .sub(user.rewardDebt);
            if (pending > 0) {
                stakedToken.transfer(address(msg.sender), pending);
            }
        }

        if (_amount > 0) {
            user.amount = user.amount.add(_amount);
            uint256 _previousBalance = stakedToken.balanceOf(address(this));
            stakedToken.transferFrom(
                address(msg.sender),
                address(this),
                _amount
            );

            uint256 _currentBalance = stakedToken.balanceOf(address(this));

            require(
                (_currentBalance - _previousBalance) >= _amount,
                "We didn't get the required amount"
            );
        }

        user.rewardDebt = user.amount.mul(accTokenPerShare).div(
            PRECISION_FACTOR
        );

        user.stakedTime = block.timestamp;

        totalStakedTokens += _amount;

        emit Deposit(msg.sender, _amount);
    }

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function withdraw(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Withdrawal amount is too high");

        require(bonusEndBlock <= block.number, "Can not withdraw now");

        _updatePool();

        uint256 pending = user
            .amount
            .mul(accTokenPerShare)
            .div(PRECISION_FACTOR)
            .sub(user.rewardDebt);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            stakedToken.transfer(address(msg.sender), _amount);
        }

        if (pending > 0) {
            stakedToken.transfer(address(msg.sender), pending);
        }

        user.rewardDebt = user.amount.mul(accTokenPerShare).div(
            PRECISION_FACTOR
        );

        totalStakedTokens -= _amount;
        emit Withdraw(msg.sender, _amount);
    }

    function changePaneltyAmount(uint256 _percentage) external onlyOwner {
        require(
            _percentage <= 50,
            "Panelty Percentage can not be greater than 50%"
        );
        earlyPenalty = _percentage;
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner
     */
    function stopReward() external onlyOwner {
        bonusEndBlock = block.number;
        poolEndAt = block.timestamp;
    }

    /*
     * @notice Update pool limit per user
     * @dev Only callable by owner.
     * @param _hasUserLimit: whether the limit remains forced
     * @param _poolLimitPerUser: new pool limit per user
     */
    function updatePoolLimitPerUser(
        bool _hasUserLimit,
        uint256 _poolLimitPerUser
    ) external onlyOwner {
        require(hasUserLimit, "Must be set");
        if (_hasUserLimit) {
            require(
                _poolLimitPerUser > poolLimitPerUser,
                "New limit must be higher"
            );
            poolLimitPerUser = _poolLimitPerUser;
        } else {
            hasUserLimit = _hasUserLimit;
            poolLimitPerUser = 0;
        }
        emit NewPoolLimit(poolLimitPerUser);
    }

    /*
     * @notice Update reward per block
     * @dev Only callable by owner.
     * @param _rewardPerBlock: the reward per block
     */
    function updateRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        require(block.number < startBlock, "Pool has started");
        rewardPerBlock = _rewardPerBlock;
        emit NewRewardPerBlock(_rewardPerBlock);
    }

    function withdrawErc20(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(msg.sender, _amount);
    }

    /**
     * @notice It allows the admin to update start and end blocks
     * @dev This function is only callable by owner.
     * @param _startBlock: the new start block
     * @param _bonusEndBlock: the new end block
     */
    function updateStartAndEndBlocks(
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) external onlyOwner {
        require(block.number < startBlock, "Pool has started");
        require(
            _startBlock < _bonusEndBlock,
            "New startBlock must be lower than new endBlock"
        );
        require(
            block.number < _startBlock,
            "New startBlock must be higher than current block"
        );

        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        // Set the lastRewardBlock as the startBlock
        lastRewardBlock = startBlock;

        emit NewStartAndEndBlocks(_startBlock, _bonusEndBlock);
    }

    /*
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        if (block.number > lastRewardBlock && totalStakedTokens != 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 cakeReward = multiplier.mul(rewardPerBlock);
            uint256 adjustedTokenPerShare = accTokenPerShare.add(
                cakeReward.mul(PRECISION_FACTOR).div(totalStakedTokens)
            );
            return
                user
                    .amount
                    .mul(adjustedTokenPerShare)
                    .div(PRECISION_FACTOR)
                    .sub(user.rewardDebt);
        } else {
            return
                user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(
                    user.rewardDebt
                );
        }
    }

    function calculateReward(uint256 _amount) external view returns (uint256) {
        if (block.number > lastRewardBlock && totalStakedTokens != 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 cakeReward = multiplier.mul(rewardPerBlock);
            uint256 adjustedTokenPerShare = accTokenPerShare.add(
                cakeReward.mul(PRECISION_FACTOR).div(totalStakedTokens)
            );
            return _amount.mul(adjustedTokenPerShare).div(PRECISION_FACTOR);
        } else {
            return _amount.mul(accTokenPerShare).div(PRECISION_FACTOR);
        }
    }

    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.number <= lastRewardBlock) {
            return;
        }

        uint256 totalAmount = totalStakedTokens;

        if (totalAmount == 0) {
            totalAmount = 1;
        }

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
        uint256 cakeReward = multiplier.mul(rewardPerBlock);
        accTokenPerShare = accTokenPerShare.add(
            cakeReward.mul(PRECISION_FACTOR).div(totalAmount)
        );
        lastRewardBlock = block.number;
    }

    /*
     * @notice Return reward multiplier over the given _from to _to block.
     * @param _from: block to start
     * @param _to: block to finish
     */
    function _getMultiplier(
        uint256 _from,
        uint256 _to
    ) internal view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from);
        }
    }

    receive() external payable {}
}

