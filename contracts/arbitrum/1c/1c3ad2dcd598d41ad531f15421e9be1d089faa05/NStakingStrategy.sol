//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {Ownable} from "./Ownable.sol";

// Interfaces
import {IStakingStrategy} from "./IStakingStrategy.sol";

contract NStakingStrategy is IStakingStrategy, Ownable {
    uint256 public balance;

    address[] public rewardTokens = new address[](0);

    address public immutable ssov;

    constructor(address _ssov) {
        ssov = _ssov;
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function stake(
        uint256 amount
    )
        external
        onlySsov(msg.sender)
        returns (uint256[] memory rewardTokenAmounts)
    {
        balance += amount;

        rewardTokenAmounts = new uint256[](0);

        emit Stake(msg.sender, amount, balance, rewardTokenAmounts);
    }

    function unstake()
        external
        onlySsov(msg.sender)
        returns (uint256[] memory rewardTokenAmounts)
    {
        rewardTokenAmounts = new uint256[](0);

        emit Unstake(msg.sender, balance, rewardTokenAmounts);
    }

    modifier onlySsov(address _sender) {
        require(_sender == ssov, "Sender must be the ssov");
        _;
    }
}

