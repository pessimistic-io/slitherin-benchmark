// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IRewarder {
    function pool() external view returns (address);

    function initialize(address pool, address reward) external returns (bool);

    function stakeFor(address account, uint amount) external;

    function withdraw(address account, uint amount) external;

    function getReward(address account) external;

    function addRewardToken(address token) external;

    function removeRewardToken(address token) external;

    function earned(
        address account,
        address[] calldata tokens
    ) external view returns (uint256[] memory);

    function claim(address account) external;

    function rewardsListLength() external view returns (uint);

    function rewards(uint) external view returns (address);
}

