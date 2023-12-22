// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

import { IBaseReward } from "./IBaseReward.sol";

contract BaseReward is Initializable, ReentrancyGuardUpgradeable, IBaseReward {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    uint256 private constant PRECISION = 1e18;

    struct User {
        uint256 totalUnderlying;
        uint256 rewards;
        uint256 rewardPerSharePaid;
    }

    address public override stakingToken;
    address public override rewardToken;
    address public operator;
    address public distributor;

    uint256 public totalSupply;
    uint256 public accRewardPerShare;
    uint256 public queuedRewards;

    mapping(address => User) public users;

    modifier onlyOperator() {
        require(operator == msg.sender, "AbstractReward: Caller is not the operator");
        _;
    }

    modifier onlyDistributor() {
        require(distributor == msg.sender, "AbstractReward: Caller is not the distributor");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(
        address _operator,
        address _distributor,
        address _stakingToken,
        address _rewardToken
    ) external initializer {
        require(_operator != address(0), "AbstractReward: _operator cannot be 0x0");
        require(_distributor != address(0), "AbstractReward: _distributor cannot be 0x0");
        require(_stakingToken != address(0), "AbstractReward: _stakingToken cannot be 0x0");
        require(_rewardToken != address(0), "AbstractReward: _rewardToken cannot be 0x0");

        require(_stakingToken.isContract(), "AbstractReward: _stakingToken is not a contract");
        require(_rewardToken.isContract(), "AbstractReward: _rewardToken is not a contract");

        __ReentrancyGuard_init();

        stakingToken = _stakingToken;
        distributor = _distributor;
        rewardToken = _rewardToken;
        operator = _operator;
    }

    function _stakeFor(address _recipient, uint256 _amountIn) internal {
        _updateRewards(_recipient);

        require(_amountIn > 0, "AbstractReward: _amountIn cannot be 0");

        {
            uint256 before = IERC20Upgradeable(stakingToken).balanceOf(address(this));
            IERC20Upgradeable(stakingToken).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(stakingToken).balanceOf(address(this)) - before;
        }

        User storage user = users[_recipient];
        user.totalUnderlying = user.totalUnderlying + _amountIn;

        totalSupply = totalSupply + _amountIn;

        emit StakeFor(_recipient, _amountIn, totalSupply, user.totalUnderlying);
    }

    function stakeFor(address _recipient, uint256 _amountIn) public virtual override nonReentrant {
        _stakeFor(_recipient, _amountIn);
    }

    function _withdraw(address _recipient, uint256 _amountOut) internal returns (uint256) {
        _updateRewards(_recipient);

        User storage user = users[_recipient];

        require(_amountOut <= user.totalUnderlying, "AbstractReward: Insufficient amounts");

        user.totalUnderlying = user.totalUnderlying - _amountOut;

        totalSupply = totalSupply - _amountOut;

        IERC20Upgradeable(stakingToken).safeTransfer(_recipient, _amountOut);

        emit Withdraw(_recipient, _amountOut, totalSupply, user.totalUnderlying);

        return _amountOut;
    }

    function withdraw(uint256 _amountOut) public virtual override nonReentrant returns (uint256) {
        return _withdraw(msg.sender, _amountOut);
    }

    function withdrawFor(address _recipient, uint256 _amountOut) public virtual override nonReentrant onlyOperator returns (uint256) {
        return _withdraw(_recipient, _amountOut);
    }

    function _updateRewards(address _recipient) internal {
        User storage user = users[_recipient];

        uint256 rewards = _checkpoint(user);

        user.rewards = rewards;
        user.rewardPerSharePaid = accRewardPerShare;
    }

    function claim(address _recipient) external override nonReentrant returns (uint256 claimed) {
        _updateRewards(_recipient);

        User storage user = users[_recipient];

        claimed = user.rewards;

        if (claimed > 0) {
            user.rewards = 0;
            IERC20Upgradeable(rewardToken).safeTransfer(_recipient, claimed);
            emit Claim(_recipient, claimed);
        }
    }

    function _checkpoint(User storage _user) internal view returns (uint256) {
        if (_user.totalUnderlying == 0) return 0;

        return _user.rewards + ((accRewardPerShare - _user.rewardPerSharePaid) * _user.totalUnderlying) / PRECISION;
    }

    function pendingRewards(address _recipient) external view override returns (uint256) {
        User storage user = users[_recipient];

        return _checkpoint(user);
    }

    function balanceOf(address _recipient) external view override returns (uint256) {
        User storage user = users[_recipient];

        return user.totalUnderlying;
    }

    function distribute(uint256 _rewards) external override nonReentrant onlyDistributor {
        if (_rewards > 0) {
            IERC20Upgradeable(rewardToken).safeTransferFrom(msg.sender, address(this), _rewards);

            if (totalSupply == 0) {
                queuedRewards = queuedRewards + _rewards;
            } else {
                _rewards = _rewards + queuedRewards;
                accRewardPerShare = accRewardPerShare + (_rewards * PRECISION) / totalSupply;
                queuedRewards = 0;

                emit Distribute(_rewards, accRewardPerShare);
            }
        }
    }
}

