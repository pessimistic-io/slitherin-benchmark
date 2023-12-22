//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {Ownable} from "./Ownable.sol";

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

// Interfaces
import {ISsovV3} from "./ISsovV3.sol";
import {IStakingStrategy} from "./IStakingStrategy.sol";
import {IERC20} from "./IERC20.sol";

contract BasicStakingStrategy is IStakingStrategy, Ownable {
    using SafeERC20 for IERC20;

    mapping(uint256 => uint256) public rewardsPerEpoch;

    mapping(uint256 => uint256) public lastTimestamp;

    uint256 public balance;

    address[] public rewardTokens = new address[](1);

    address public immutable ssov;

    event NewRewards(uint256 epoch, uint256 rewards);

    constructor(address _ssov, address _rewardToken) {
        ssov = _ssov;
        rewardTokens[0] = _rewardToken;
    }

    function updateRewardsPerEpoch(uint256 _rewards, uint256 _epoch)
        external
        onlyOwner
    {
        rewardsPerEpoch[_epoch] = _rewards;
        emit NewRewards(_rewards, _epoch);
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function stake(uint256 amount)
        external
        onlySsov(msg.sender)
        returns (uint256[] memory rewardTokenAmounts)
    {
        ISsovV3 _ssov = ISsovV3(ssov);

        uint256 epoch = _ssov.currentEpoch();

        (uint256 startTime, uint256 expiry) = _ssov.getEpochTimes(epoch);

        uint256 rewardRate = rewardsPerEpoch[epoch] / (expiry - startTime);

        balance += amount;

        uint256 rewardsEmitted = rewardRate * (block.timestamp - startTime);

        rewardTokenAmounts = new uint256[](1);

        rewardTokenAmounts[0] = rewardsEmitted;

        emit Stake(msg.sender, amount, balance, rewardTokenAmounts);
    }

    function unstake()
        external
        onlySsov(msg.sender)
        returns (uint256[] memory rewardTokenAmounts)
    {
        ISsovV3 _ssov = ISsovV3(ssov);

        uint256 epoch = _ssov.currentEpoch();

        rewardTokenAmounts = new uint256[](1);

        rewardTokenAmounts[0] = rewardsPerEpoch[epoch];

        IERC20(rewardTokens[0]).safeTransfer(
            msg.sender,
            rewardsPerEpoch[epoch]
        );

        emit Unstake(msg.sender, balance, rewardTokenAmounts);
    }

    modifier onlySsov(address _sender) {
        require(_sender == ssov, "Sender must be the ssov");
        _;
    }
}

