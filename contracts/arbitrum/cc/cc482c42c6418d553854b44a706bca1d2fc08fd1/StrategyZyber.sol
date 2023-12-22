// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {DuoBaseStrategy} from "./DuoBaseStrategy.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {IZyberChef} from "./IZyberChef.sol";
import {IDuoMaster} from "./IDuoMaster.sol";

contract StrategyZyber is DuoBaseStrategy {
    using SafeERC20 for IERC20;

    // zyber
    IERC20 public constant rewardToken =
        IERC20(0x3B475F6f2f41853706afc9Fa6a6b8C5dF1a2724c);

    // zyber masterchef contract ( 0x9BA666165867E916Ee7Ed3a3aE6C19415C2fBDDD )
    IZyberChef public immutable stakingContract;
    // pid zyber chef
    uint256 public immutable pid; //
    uint256 public immutable pidMonopoly;
    //total harvested by the contract all time
    uint256 public totalHarvested;

    //total amount harvested by each user
    mapping(address => uint256) public harvested;

    bool public isHarvesting = true;

    event Harvest(
        address indexed caller,
        address indexed to,
        uint256 harvestedAmount
    );

    constructor(
        IDuoMaster _duoMaster,
        IERC20 _depositToken,
        uint256 _pid,
        uint256 _pidMonopoly,
        IZyberChef _stakingContract
    ) DuoBaseStrategy(_duoMaster, _depositToken) {
        pid = _pid;
        pidMonopoly = _pidMonopoly;
        stakingContract = _stakingContract;
        _depositToken.safeApprove(address(_stakingContract), MAX_UINT);
    }

    //PUBLIC FUNCTIONS
    /**
     * @notice Reward token balance that can be claimed
     * @dev Staking rewards accrue to contract on each deposit/withdrawal
     * @return Unclaimed rewards
     */
    function checkReward() public view returns (uint256) {
        (, , , uint256[] memory amounts) = stakingContract.pendingTokens(
            pid,
            address(this)
        );
        return amounts[0];
    }

    function pendingRewards(address user) public view returns (uint256) {
        uint256 unclaimedRewards = checkReward();
        return unclaimedRewards;
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
        if (isHarvesting) {
            _claimRewards();
            _harvest(caller, to);
        }
        if (tokenAmount > 0) {
            stakingContract.deposit(pid, tokenAmount);
        }
    }

    function withdraw(
        address caller,
        address to,
        uint256 tokenAmount,
        uint256 shareAmount,
        uint256 withdrawalFeeBP
    ) external override onlyOwner {
        // if admin set not to harvest, then withdraw directly from staking contract
        if (!isHarvesting) {
            if (tokenAmount > 0) {
                stakingContract.emergencyWithdraw(pid);
                if (withdrawalFeeBP > 0) {
                    uint256 withdrawalFee = (tokenAmount * withdrawalFeeBP) /
                        10000;
                    depositToken.safeTransfer(
                        duoMaster.actionFeeAddress(),
                        withdrawalFee
                    );
                    tokenAmount -= withdrawalFee;
                }
                depositToken.safeTransfer(to, tokenAmount);
            }
        } else {
            _claimRewards();
            _harvest(caller, to);
            if (tokenAmount > 0) {
                stakingContract.withdraw(pid, tokenAmount);
                if (withdrawalFeeBP > 0) {
                    uint256 withdrawalFee = (tokenAmount * withdrawalFeeBP) /
                        10000;
                    depositToken.safeTransfer(
                        duoMaster.actionFeeAddress(),
                        withdrawalFee
                    );
                    tokenAmount -= withdrawalFee;
                }
                depositToken.safeTransfer(to, tokenAmount);
            }
        }
    }

    function emergencyWithdraw(
        address,
        address to,
        uint256 tokenAmount,
        uint256 shareAmount,
        uint256 withdrawalFeeBP
    ) external override onlyOwner {
        if (!isHarvesting) {
            if (tokenAmount > 0) {
                stakingContract.emergencyWithdraw(pid);
                if (withdrawalFeeBP > 0) {
                    uint256 withdrawalFee = (tokenAmount * withdrawalFeeBP) /
                        10000;
                    depositToken.safeTransfer(
                        duoMaster.actionFeeAddress(),
                        withdrawalFee
                    );
                    tokenAmount -= withdrawalFee;
                }
                depositToken.safeTransfer(to, tokenAmount);
            }
        } else {
            if (tokenAmount > 0) {
                stakingContract.withdraw(pid, tokenAmount);
                if (withdrawalFeeBP > 0) {
                    uint256 withdrawalFee = (tokenAmount * withdrawalFeeBP) /
                        10000;
                    depositToken.safeTransfer(
                        duoMaster.actionFeeAddress(),
                        withdrawalFee
                    );
                    tokenAmount -= withdrawalFee;
                }
                depositToken.safeTransfer(to, tokenAmount);
            }
        }
    }

    function migrate(address newStrategy) external override onlyOwner {
        if (!isHarvesting) {
            stakingContract.emergencyWithdraw(pid);
            depositToken.safeTransfer(
                newStrategy,
                depositToken.balanceOf(address(this))
            );
        } else {
            _claimRewards();
            (uint256 toWithdraw, , , ) = stakingContract.userInfo(
                pid,
                address(this)
            );
            if (toWithdraw > 0) {
                stakingContract.withdraw(pid, toWithdraw);
                depositToken.safeTransfer(newStrategy, toWithdraw);
            }
            uint256 rewardsToTransfer = rewardToken.balanceOf(address(this));
            if (rewardsToTransfer > 0) {
                rewardToken.safeTransfer(newStrategy, rewardsToTransfer);
            }
        }
    }

    function onMigration() external override onlyOwner {
        uint256 toStake = depositToken.balanceOf(address(this));
        stakingContract.deposit(pid, toStake);
    }

    function setAllowances() external override onlyOwner {
        depositToken.safeApprove(address(stakingContract), 0);
        depositToken.safeApprove(address(stakingContract), MAX_UINT);
    }

    //INTERNAL FUNCTIONS
    //claim any as-of-yet unclaimed rewards
    function _claimRewards() internal {
        uint256 unclaimedRewards = checkReward();
        uint256 totalShares = duoMaster.totalShares(pidMonopoly);
        if (unclaimedRewards > 0 && totalShares > 0) {
            stakingContract.deposit(pid, 0);
        }
    }

    function _harvest(address caller, address to) internal {
        uint256 rewardAmount = rewardToken.balanceOf(address(this));
        _safeRewardTokenTransfer(
            duoMaster.performanceFeeAddress(),
            rewardAmount
        );
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

    function setHarvesting(bool _isHarvesting) external {
        require(
            msg.sender == duoMaster.owner(),
            "only owner address can set harvesting"
        );
        stakingContract.deposit(pid, depositToken.balanceOf(address(this)));
        isHarvesting = _isHarvesting;
    }
}

