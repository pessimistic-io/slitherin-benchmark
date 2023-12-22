// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SafeMath} from "./SafeMath.sol";

import {ERC20Proxy, IERC20} from "./ERC20Proxy.sol";
import {IMiniChefV2} from "./IMiniChefV2.sol";
import {FeeBase} from "./FeeBase.sol";
import {VersionedInitializable} from "./VersionedInitializable.sol";

/**
 * @title The sushi masterchef tokenzied for a specific pool
 */
contract WMasterChefV2 is
    VersionedInitializable,
    FeeBase,
    ERC20Proxy,
    ReentrancyGuard
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public pid;
    IMiniChefV2 public chef; // Sushiswap masterChef
    IERC20 public rewardToken; // sushi
    IERC20 public lpToken;
    address public me;

    function initialize(
        string memory _name,
        string memory _symbol,
        IMiniChefV2 _chef,
        uint256 _pid,
        address _lpToken,
        address _rewardToken,
        address _rewardDestination,
        uint256 _rewardFee,
        address _governance
    ) external initializer {
        initializeERC20(_name, _symbol);
        initializeFeeBase(_rewardFee, _rewardDestination, _governance);

        chef = _chef;
        lpToken = IERC20(_lpToken);
        rewardToken = IERC20(_rewardToken);
        pid = _pid;
        me = address(this);

        lpToken.approve(address(chef), type(uint256).max);
    }

    function getRevision() public pure virtual override returns (uint256) {
        return 0;
    }

    function _depositFor(
        address account,
        uint256 amount
    ) internal returns (bool) {
        // take the LP tokens
        lpToken.safeTransferFrom(account, me, amount);

        // stake into the masterchef contract
        chef.deposit(pid, amount, me);

        _mint(account, amount);
        return true;
    }

    function deposit(uint256 amount) external nonReentrant returns (bool) {
        return _depositFor(msg.sender, amount);
    }

    /// @dev Burn ERC20 token to redeem LP ERC20 token back plus SUSHI rewards.
    /// @param amount Token amount to burn
    function withdraw(uint256 amount) external nonReentrant returns (bool) {
        harvest();

        // calculate accumulated rewards
        uint256 earnings = _accumulatedRewardsForAmount(amount);

        // withdraw and send the lp token back
        _burn(msg.sender, amount);
        chef.withdraw(pid, amount, msg.sender);

        rewardToken.transfer(msg.sender, earnings);
        return true;
    }

    function rewardTokenBalance() public view returns (uint256) {
        return rewardToken.balanceOf(me);
    }

    // capture rewards and send the fees to the governance contract
    function harvest() public {
        uint256 balBefore = rewardTokenBalance();
        chef.harvest(pid, me);
        uint256 earnings = rewardTokenBalance().sub(balBefore);
        _chargeFee(rewardToken, earnings);
    }

    function _accumulatedRewards() internal view virtual returns (uint256) {
        return chef.pendingSushi(pid, me) + rewardTokenBalance();
    }

    function accumulatedRewards() external view returns (uint256) {
        return _accumulatedRewards();
    }

    function accumulatedRewardsFor(
        address _user
    ) external view returns (uint256) {
        return _accumulatedRewardsFor(_user);
    }

    function _accumulatedRewardsFor(
        address _user
    ) internal view returns (uint256) {
        uint256 bal = balanceOf(_user);
        return _accumulatedRewardsForAmount(bal);
    }

    function _accumulatedRewardsForAmount(
        uint256 bal
    ) internal view returns (uint256) {
        uint256 accRewards = _accumulatedRewards();
        uint256 total = totalSupply();
        uint256 perc = bal.mul(1e18).div(total);
        return accRewards.mul(perc).div(1e18);
    }
}

