// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {BaseStrategy} from "./BaseStrategy.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {StrategyStorage} from "./StrategyStorage.sol";
import {MonoMaster} from "./MonoMaster.sol";

contract StrategyMonopoly is BaseStrategy {
    using SafeERC20 for IERC20;

    StrategyStorage public immutable strategyStorage;
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
        uint256 _pidMonopoly
    ) BaseStrategy(_monoMaster, _depositToken) {
        pidMonopoly = _pidMonopoly;
        strategyStorage = new StrategyStorage();
    }

    //PUBLIC FUNCTIONS
    /**
     * @notice Reward token balance that can be claimed
     * @dev Staking rewards accrue to contract on each deposit/withdrawal
     * @return Unclaimed rewards
     */
    function checkReward() public view returns (uint256) {
        return 0;
    }

    function pendingRewards(address user) public view returns (uint256) {
        return 0;
    }

    function rewardTokens() external view virtual returns (address[] memory) {
        address[] memory _rewardTokens = new address[](1);
        return (_rewardTokens);
    }

    function pendingTokens(
        uint256,
        address user,
        uint256
    ) external view override returns (address[] memory, uint256[] memory) {
        address[] memory _rewardTokens = new address[](1);
        _rewardTokens[0] = address(0);
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
            // stakingContract.deposit(pid, tokenAmount);
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
        if (tokenAmount > 0) {
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
    }

    function migrate(address newStrategy) external override onlyOwner {
        uint256 toWithdraw = depositToken.balanceOf(address(this));
        if (toWithdraw > 0) {
            depositToken.safeTransfer(newStrategy, toWithdraw);
        }
    }

    function onMigration() external override onlyOwner {}

    function setAllowances() external override onlyOwner {}

    //INTERNAL FUNCTIONS
    //claim any as-of-yet unclaimed rewards
    function _claimRewards() internal {}

    function _harvest(address caller, address to) internal {}

    //internal wrapper function to avoid reverts due to rounding
    function _safeRewardTokenTransfer(address user, uint256 amount) internal {}
}

