// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;
import {ERC20} from "./ERC20.sol";

interface IStaker{

    struct LockedStake {
        bytes32 kek_id;
        uint256 start_timestamp;
        uint256 amount;
        uint256 ending_timestamp;
        uint256 multiplier; // 6 decimals of precision. 1x = 1000000
    }

    function rewardsToken0() external view returns(ERC20); //FXS
    function rewardsToken1() external view returns(ERC20); //VSTA

    function stakingToken() external view returns(ERC20);

    function periodFinish() external view returns(uint256);

    function lock_time_min() external view returns(uint256);

    //Returns the amount claimbale for each reward token
    function rewards0() external view returns(uint256); //FXS
    function rewards1() external view returns(uint256); //VSTA

    function earned(address _address) external view returns(uint256, uint256);

    function balanceOf(address account) external view returns (uint256);

    function lockedLiquidityOf(address account) external view returns (uint256);
    function unlockedBalanceOf(address account) external view returns (uint256);

    function lockedStakesOf(address _address) external view returns(LockedStake[] memory);

    function stakeLocked(uint256 amount, uint256 secs) external;

    function withdrawLocked(bytes32 kek_id) external;

    //Claim rewards
    function getReward() external;

}

