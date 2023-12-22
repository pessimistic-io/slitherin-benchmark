// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

import { ICreditManager } from "./ICreditManager.sol";
import { IAbstractVault } from "./IAbstractVault.sol";
import { IShareLocker } from "./IShareLocker.sol";
import { IBaseReward } from "./IBaseReward.sol";

contract CreditManager is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, ICreditManager {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    uint256 private constant PRECISION = 1e18;

    address public override vault;
    address public caller;
    address public rewardTracker;
    uint256 public totalShares;
    uint256 public accRewardPerShare;
    uint256 public queuedRewards;

    struct User {
        uint256 shares;
        uint256 rewards;
        uint256 rewardPerSharePaid;
    }

    mapping(address => User) public users;

    modifier onlyCaller() {
        require(caller == msg.sender, "CreditManager: Caller is not the caller");
        _;
    }

    modifier onlyRewardTracker() {
        require(rewardTracker == msg.sender, "CreditManager: Caller is not the reward tracker");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(
        address _vault,
        address _caller,
        address _rewardTracker
    ) external initializer {
        require(_vault != address(0), "CreditManager: _vault cannot be 0x0");
        require(_caller != address(0), "CreditManager: _caller cannot be 0x0");
        require(_rewardTracker != address(0), "CreditManager: _rewardTracker cannot be 0x0");

        require(_vault.isContract(), "CreditManager: _vault is not a contract");
        require(_caller.isContract(), "CreditManager: _caller is not a contract");
        require(_rewardTracker.isContract(), "CreditManager: _rewardTracker is not a contract");

        __ReentrancyGuard_init();

        vault = _vault;
        caller = _caller;
        rewardTracker = _rewardTracker;
    }

    function borrow(address _recipient, uint256 _borrowedAmount) external override onlyCaller {
        _updateRewards(_recipient);

        User storage user = users[_recipient];

        address underlyingToken = IAbstractVault(vault).underlyingToken();
        uint256 shares = IAbstractVault(vault).borrow(_borrowedAmount);

        IERC20Upgradeable(underlyingToken).safeTransfer(msg.sender, _borrowedAmount);

        totalShares = totalShares + shares;
        user.shares = user.shares + shares;

        emit Borrow(_recipient, _borrowedAmount, totalShares, user.shares);
    }

    function repay(address _recipient, uint256 _borrowedAmount) external override onlyCaller {
        _updateRewards(_recipient);

        address underlyingToken = IAbstractVault(vault).underlyingToken();

        IERC20Upgradeable(underlyingToken).safeTransferFrom(msg.sender, address(this), _borrowedAmount);

        _approve(underlyingToken, vault, _borrowedAmount);

        User storage user = users[_recipient];
        totalShares = totalShares - _borrowedAmount;
        user.shares = user.shares - _borrowedAmount;

        IAbstractVault(vault).repay(_borrowedAmount);

        emit Repay(_recipient, _borrowedAmount, totalShares, user.shares);
    }

    function harvest() external override nonReentrant onlyRewardTracker returns (uint256) {
        address shareLocker = IAbstractVault(vault).creditManagersShareLocker(address(this));
        uint256 claimed = IShareLocker(shareLocker).harvest();

        if (claimed > 0) {
            if (totalShares == 0) {
                queuedRewards = queuedRewards + claimed;
            } else {
                claimed = claimed + queuedRewards;
                accRewardPerShare = accRewardPerShare + (claimed * PRECISION) / totalShares;
                queuedRewards = 0;

                emit Harvest(claimed, accRewardPerShare);
            }
        }

        return claimed;
    }

    function _updateRewards(address _recipient) internal {
        User storage user = users[_recipient];

        uint256 rewards = _checkpoint(user);

        user.rewards = rewards;
        user.rewardPerSharePaid = accRewardPerShare;
    }

    function claim(address _recipient) external override nonReentrant returns (uint256 claimed) {
        _updateRewards(_recipient);

        address rewardPool = IAbstractVault(vault).borrowedRewardPool();
        address rewardToken = IBaseReward(rewardPool).rewardToken();

        User storage user = users[_recipient];

        claimed = user.rewards;

        if (claimed > 0) {
            IERC20Upgradeable(rewardToken).safeTransfer(_recipient, claimed);

            emit Claim(_recipient, claimed);
        }

        user.rewards = 0;
    }

    function _checkpoint(User storage _user) internal view returns (uint256) {
        if (_user.shares == 0) return 0;

        return _user.rewards + ((accRewardPerShare - _user.rewardPerSharePaid) * _user.shares) / PRECISION;
    }

    function pendingRewards(address _recipient) public view returns (uint256) {
        User storage user = users[_recipient];

        return _checkpoint(user);
    }

    function balanceOf(address _recipient) external view override returns (uint256) {
        User storage user = users[_recipient];

        return user.shares;
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }
}

