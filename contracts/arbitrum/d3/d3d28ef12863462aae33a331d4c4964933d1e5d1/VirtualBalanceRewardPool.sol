// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./OwnableUpgradeable.sol";

import "./IVirtualBalanceRewardPool.sol";
import "./IWombatBooster.sol";
import "./TransferHelper.sol";

contract VirtualBalanceRewardPool is
    IVirtualBalanceRewardPool,
    OwnableUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using TransferHelper for address;

    address public operator;

    address[] public rewardTokens;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    struct Reward {
        uint256 rewardPerTokenStored;
        uint256 queuedRewards;
    }

    struct UserReward {
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
    }

    mapping(address => Reward) public rewards;
    mapping(address => bool) public isRewardToken;

    mapping(address => mapping(address => UserReward)) public userRewards;

    mapping(address => bool) public access;

    mapping(address => uint256) public userLastTime;

    mapping(address => uint256) public userAmountTime;

    function initialize(address _operator) public initializer {
        __Ownable_init();

        operator = _operator;

        access[operator] = true;

        emit OperatorUpdated(_operator);
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "Only Operator");
        _;
    }

    function addRewardToken(address _rewardToken) internal {
        require(_rewardToken != address(0), "invalid _rewardToken!");
        if (isRewardToken[_rewardToken]) {
            return;
        }
        rewardTokens.push(_rewardToken);
        isRewardToken[_rewardToken] = true;

        emit RewardTokenAdded(_rewardToken);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    modifier updateReward(address _account) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            UserReward storage userReward = userRewards[_account][rewardToken];
            userReward.rewards = earned(_account, rewardToken);
            userReward.userRewardPerTokenPaid = rewards[rewardToken]
                .rewardPerTokenStored;
        }

        userAmountTime[_account] = getUserAmountTime(_account);
        userLastTime[_account] = now;

        _;
    }

    function getRewardTokens()
        external
        view
        override
        returns (address[] memory)
    {
        return rewardTokens;
    }

    function getRewardTokensLength() external view override returns (uint256) {
        return rewardTokens.length;
    }

    function earned(address _account, address _rewardToken)
        public
        view
        override
        returns (uint256)
    {
        Reward memory reward = rewards[_rewardToken];
        UserReward memory userReward = userRewards[_account][_rewardToken];
        return
            balanceOf(_account)
                .mul(
                    reward.rewardPerTokenStored.sub(
                        userReward.userRewardPerTokenPaid
                    )
                )
                .div(1e18)
                .add(userReward.rewards);
    }

    function getUserAmountTime(address _account)
        public
        view
        override
        returns (uint256)
    {
        uint256 lastTime = userLastTime[_account];
        if (lastTime == 0) {
            return 0;
        }
        uint256 userBalance = _balances[_account];
        if (userBalance == 0) {
            return userAmountTime[_account];
        }
        return userAmountTime[_account].add(now.sub(lastTime).mul(userBalance));
    }

    function stakeFor(address _for, uint256 _amount)
        external
        override
        onlyOperator
        updateReward(_for)
    {
        require(_for != address(0), "invalid _for!");
        require(_amount > 0, "RewardPool : Cannot stake 0");

        //give to _for
        _totalSupply = _totalSupply.add(_amount);
        _balances[_for] = _balances[_for].add(_amount);

        emit Staked(_for, _amount);
    }

    function withdrawFor(address _account, uint256 _amount)
        external
        override
        onlyOperator
        updateReward(_account)
    {
        require(_amount > 0, "RewardPool : Cannot withdraw 0");

        _totalSupply = _totalSupply.sub(_amount);
        _balances[_account] = _balances[_account].sub(_amount);

        emit Withdrawn(_account, _amount);

        getReward(_account);
    }

    function getReward(address _account)
        public
        override
        onlyOperator
        updateReward(_account)
    {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            uint256 reward = earned(_account, rewardToken);
            if (reward > 0) {
                userRewards[_account][rewardToken].rewards = 0;
                rewardToken.safeTransferToken(_account, reward);
                emit RewardPaid(_account, rewardToken, reward);
            }
        }
    }

    function donate(address _rewardToken, uint256 _amount)
        external
        payable
        override
    {
        require(isRewardToken[_rewardToken], "invalid token");
        if (AddressLib.isPlatformToken(_rewardToken)) {
            require(_amount == msg.value, "invalid amount");
        } else {
            require(msg.value == 0, "invalid msg.value");
            IERC20(_rewardToken).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }

        rewards[_rewardToken].queuedRewards = rewards[_rewardToken]
            .queuedRewards
            .add(_amount);
    }

    function queueNewRewards(address _rewardToken, uint256 _rewards)
        external
        payable
        override
    {
        require(access[msg.sender], "!auth");

        addRewardToken(_rewardToken);

        if (AddressLib.isPlatformToken(_rewardToken)) {
            require(_rewards == msg.value, "invalid amount");
        } else {
            require(msg.value == 0, "invalid msg.value");
            IERC20(_rewardToken).safeTransferFrom(
                msg.sender,
                address(this),
                _rewards
            );
        }

        Reward storage rewardInfo = rewards[_rewardToken];

        if (totalSupply() == 0) {
            rewardInfo.queuedRewards = rewardInfo.queuedRewards.add(_rewards);
            return;
        }

        _rewards = _rewards.add(rewardInfo.queuedRewards);
        rewardInfo.queuedRewards = 0;

        rewardInfo.rewardPerTokenStored = rewardInfo.rewardPerTokenStored.add(
            _rewards.mul(1e18).div(totalSupply())
        );
        emit RewardAdded(_rewardToken, _rewards);
    }

    function setAccess(address _address, bool _status)
        external
        override
        onlyOwner
    {
        require(_address != address(0), "invalid _address!");

        access[_address] = _status;
        emit AccessSet(_address, _status);
    }

    receive() external payable {}
}

