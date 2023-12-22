// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {BaseStrategy} from "./BaseStrategy.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {StrategyStorage} from "./StrategyStorage.sol";
import {ISushiChef} from "./ISushiChef.sol";
import {MonoMaster} from "./MonoMaster.sol";

contract StrategySushi is BaseStrategy {
    using SafeERC20 for IERC20;

    // sushi
    IERC20 public constant rewardToken =
        IERC20(0xd4d42F0b6DEF4CE0383636770eF773390d85c61A);
    // sushi masterchef contract
    ISushiChef public immutable stakingContract;
    StrategyStorage public immutable strategyStorage;
    uint256 public immutable pid; //
    uint256 public immutable pidMonopoly;
    //total harvested by the contract all time
    uint256 public totalHarvested;

    //total amount harvested by each user
    mapping(address => uint256) public harvested;

    event Harvest(
        address indexed caller,
        address indexed to,
        uint256 harvestedAmount
    );

    constructor(
        MonoMaster _monoMaster,
        IERC20 _depositToken,
        uint256 _pid,
        uint256 _pidMonopoly,
        ISushiChef _stakingContract
    ) BaseStrategy(_monoMaster, _depositToken) {
        pid = _pid;
        pidMonopoly = _pidMonopoly;
        stakingContract = _stakingContract;
        strategyStorage = new StrategyStorage();
        _depositToken.safeApprove(address(_stakingContract), MAX_UINT);
    }

    //PUBLIC FUNCTIONS
    /**
     * @notice Reward token balance that can be claimed
     * @dev Staking rewards accrue to contract on each deposit/withdrawal
     * @return Unclaimed rewards
     */
    function checkReward() public view returns (uint256) {
        uint256 amount = stakingContract.pendingSushi(pid, address(this));
        return amount;
    }

    function pendingRewards(address user) public view returns (uint256) {
        uint256 userShares = monoMaster.userShares(pidMonopoly, user);
        uint256 unclaimedRewards = checkReward();
        uint256 rewardTokensPerShare = strategyStorage.rewardTokensPerShare();
        uint256 totalShares = monoMaster.totalShares(pidMonopoly);
        uint256 userRewardDebt = strategyStorage.rewardDebt(user);
        uint256 multiplier = rewardTokensPerShare;
        if (totalShares > 0) {
            multiplier =
                multiplier +
                ((unclaimedRewards * ACC_EARNING_PRECISION) / totalShares);
        }
        uint256 totalRewards = (userShares * multiplier) /
            ACC_EARNING_PRECISION;
        uint256 userPendingRewards = (totalRewards >= userRewardDebt)
            ? (totalRewards - userRewardDebt)
            : 0;
        return userPendingRewards;
    }

    function rewardTokens() external view virtual returns (address[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(rewardToken);
        return (_rewardTokens);
    }

    function pendingTokens(
        uint256,
        address user,
        uint256
    ) external view override returns (address[] memory, uint256[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(rewardToken);
        uint256[] memory _pendingAmounts = new uint256[](1);
        _pendingAmounts[0] = pendingRewards(user);
        return (_rewardTokens, _pendingAmounts);
    }

    //EXTERNAL FUNCTIONS
    function harvest() external {
        _claimRewards();
        _harvest(msg.sender, msg.sender);
    }

    //OWNER-ONlY FUNCTIONS
    function deposit(
        address caller,
        address to,
        uint256 tokenAmount,
        uint256 shareAmount
    ) external override onlyOwner {
        _claimRewards();
        _harvest(caller, to);
        if (tokenAmount > 0) {
            stakingContract.deposit(pid, tokenAmount, address(this));
        }
        if (shareAmount > 0) {
            strategyStorage.increaseRewardDebt(to, shareAmount);
        }
    }

    function withdraw(
        address caller,
        address to,
        uint256 tokenAmount,
        uint256 shareAmount,
        uint256 withdrawalFeeBP
    ) external override onlyOwner {
        _claimRewards();
        _harvest(caller, to);
        if (tokenAmount > 0) {
            stakingContract.withdraw(pid, tokenAmount, address(this));
            if (withdrawalFeeBP > 0) {
                uint256 withdrawalFee = (tokenAmount * withdrawalFeeBP) / 10000;
                depositToken.safeTransfer(
                    monoMaster.actionFeeAddress(),
                    withdrawalFee
                );
                tokenAmount -= withdrawalFee;
            }
            depositToken.safeTransfer(to, tokenAmount);
        }
        if (shareAmount > 0) {
            strategyStorage.decreaseRewardDebt(to, shareAmount);
        }
    }

    function emergencyWithdraw(
        address,
        address to,
        uint256 tokenAmount,
        uint256 shareAmount,
        uint256 withdrawalFeeBP
    ) external override onlyOwner {
        if (tokenAmount > 0) {
            stakingContract.withdraw(pid, tokenAmount, address(this));
            if (withdrawalFeeBP > 0) {
                uint256 withdrawalFee = (tokenAmount * withdrawalFeeBP) / 10000;
                depositToken.safeTransfer(
                    monoMaster.actionFeeAddress(),
                    withdrawalFee
                );
                tokenAmount -= withdrawalFee;
            }
            depositToken.safeTransfer(to, tokenAmount);
        }
        if (shareAmount > 0) {
            strategyStorage.decreaseRewardDebt(to, shareAmount);
        }
    }

    function migrate(address newStrategy) external override onlyOwner {
        _claimRewards();
        (uint256 toWithdraw, ) = stakingContract.userInfo(pid, address(this));
        if (toWithdraw > 0) {
            stakingContract.withdraw(pid, toWithdraw, address(this));
            depositToken.safeTransfer(newStrategy, toWithdraw);
        }
        uint256 rewardsToTransfer = rewardToken.balanceOf(address(this));
        if (rewardsToTransfer > 0) {
            rewardToken.safeTransfer(newStrategy, rewardsToTransfer);
        }
        strategyStorage.transferOwnership(newStrategy);
    }

    function onMigration() external override onlyOwner {
        uint256 toStake = depositToken.balanceOf(address(this));
        stakingContract.deposit(pid, toStake, address(this));
    }

    function setAllowances() external override onlyOwner {
        depositToken.safeApprove(address(stakingContract), 0);
        depositToken.safeApprove(address(stakingContract), MAX_UINT);
    }

    //INTERNAL FUNCTIONS
    //claim any as-of-yet unclaimed rewards
    function _claimRewards() internal {
        uint256 unclaimedRewards = checkReward();
        uint256 totalShares = monoMaster.totalShares(pidMonopoly);
        if (unclaimedRewards > 0 && totalShares > 0) {
            stakingContract.harvest(pid, address(this));
            strategyStorage.increaseRewardTokensPerShare(
                (unclaimedRewards * ACC_EARNING_PRECISION) / totalShares
            );
        }
    }

    function _harvest(address caller, address to) internal {
        uint256 userShares = monoMaster.userShares(pidMonopoly, caller);
        uint256 totalRewards = (userShares *
            strategyStorage.rewardTokensPerShare()) / ACC_EARNING_PRECISION;
        uint256 userRewardDebt = strategyStorage.rewardDebt(caller);
        uint256 userPendingRewards = (totalRewards >= userRewardDebt)
            ? (totalRewards - userRewardDebt)
            : 0;
        strategyStorage.setRewardDebt(caller, userShares);
        if (userPendingRewards > 0) {
            totalHarvested += userPendingRewards;
            if (performanceFeeBips > 0) {
                uint256 performanceFee = (userPendingRewards *
                    performanceFeeBips) / MAX_BIPS;
                _safeRewardTokenTransfer(
                    monoMaster.performanceFeeAddress(),
                    performanceFee
                );
                userPendingRewards = userPendingRewards - performanceFee;
            }
            harvested[to] += userPendingRewards;
            emit Harvest(caller, to, userPendingRewards);
            _safeRewardTokenTransfer(to, userPendingRewards);
        }
    }

    //internal wrapper function to avoid reverts due to rounding
    function _safeRewardTokenTransfer(address user, uint256 amount) internal {
        uint256 rewardTokenBal = rewardToken.balanceOf(address(this));
        if (amount > rewardTokenBal) {
            rewardToken.safeTransfer(user, rewardTokenBal);
        } else {
            rewardToken.safeTransfer(user, amount);
        }
    }
}

