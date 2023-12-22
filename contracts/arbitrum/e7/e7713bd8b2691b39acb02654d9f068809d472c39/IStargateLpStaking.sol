// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IStargateLpStaking {
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function balanceOf(address _owner) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function totalLiquidity() external view returns (uint256);

    function poolLength() external view returns (uint256);

    function getPoolInfo(uint256) external view returns (address);
    
    function userInfo(uint256, address) external view returns (UserInfo calldata);
}

