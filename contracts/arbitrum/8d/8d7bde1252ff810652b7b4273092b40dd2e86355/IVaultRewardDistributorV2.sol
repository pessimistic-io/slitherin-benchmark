// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IVaultRewardDistributorV2 {
    function stake(uint256 _amountIn) external;

    function withdraw(uint256 _amountOut) external returns (uint256);

    function distribute(uint256 _rewards) external;

    event Distribute(address _pool, uint256 _totalRewards, uint256 _rewards);
    event SetSupplyRewardPoolRatio(uint256 _ratio);
    event SetBorrowedRewardPoolRatio(uint256 _ratio);
    event SetPool(bytes32 _key, address _stakingToken, address _rewardToken, address _pool);
    event NewStaker(address indexed _sender, address _staker);
    event RemoveStaker(address indexed _sender, address _staker);
    event NewDistributor(address indexed _sender, address _distributor);
    event RemoveDistributor(address indexed _sender, address _distributor);
    event Stake(uint256 _amountIn);
    event Withdraw(uint256 _amountOut);
}

