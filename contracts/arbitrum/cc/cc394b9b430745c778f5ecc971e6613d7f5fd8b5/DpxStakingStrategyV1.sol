//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {Ownable} from "./Ownable.sol";

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

// Interfaces
import {IStakingStrategy} from "./IStakingStrategy.sol";
import {IStakingRewards} from "./IStakingRewards.sol";
import {IERC20} from "./IERC20.sol";

/// @title Stakes DPX into the DPX single sided farm on Arbitrum
contract DpxStakingStrategyV1 is IStakingStrategy, Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IStakingRewards;

    IStakingRewards public constant STAKING_REWARDS =
        IStakingRewards(0xc6D714170fE766691670f12c2b45C1f34405AAb6);

    IERC20 public constant DPX =
        IERC20(0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55);

    IERC20 public constant RDPX =
        IERC20(0x32Eb7902D4134bf98A28b963D26de779AF92A212);

    address[] public rewardTokens = new address[](2);

    address public immutable ssov;

    constructor(
        address _stakingRewards,
        address _ssov,
        address[] memory _rewardTokens
    ) {
        ssov = _ssov;

        DPX.safeIncreaseAllowance(address(_stakingRewards), type(uint256).max);

        rewardTokens = _rewardTokens;
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function stake(uint256 amount)
        external
        onlySsov(msg.sender)
        returns (uint256[] memory rewardTokenAmounts)
    {
        // Transfer DPX from sender
        DPX.safeTransferFrom(msg.sender, address(this), amount);

        rewardTokenAmounts = new uint256[](2);
        (rewardTokenAmounts[0], rewardTokenAmounts[1]) = STAKING_REWARDS.earned(
            address(this)
        );

        // Deposit DPX into the farm
        STAKING_REWARDS.stake(amount);

        uint256 totalStakedBalance = STAKING_REWARDS.balanceOf(address(this));

        emit Stake(msg.sender, amount, totalStakedBalance, rewardTokenAmounts);
    }

    function unstake()
        external
        onlySsov(msg.sender)
        returns (uint256[] memory rewardTokenAmounts)
    {
        rewardTokenAmounts = new uint256[](2);
        (rewardTokenAmounts[0], rewardTokenAmounts[1]) = STAKING_REWARDS.earned(
            address(this)
        );
        uint256 balance = STAKING_REWARDS.balanceOf(address(this));

        // claim rewards and unstake
        STAKING_REWARDS.exit();

        DPX.safeTransfer(msg.sender, rewardTokenAmounts[0]);
        RDPX.safeTransfer(msg.sender, rewardTokenAmounts[1]);

        DPX.safeTransfer(msg.sender, balance);

        emit Unstake(msg.sender, balance, rewardTokenAmounts);
    }

    modifier onlySsov(address _sender) {
        require(_sender == ssov, "Sender must be the ssov");
        _;
    }
}

