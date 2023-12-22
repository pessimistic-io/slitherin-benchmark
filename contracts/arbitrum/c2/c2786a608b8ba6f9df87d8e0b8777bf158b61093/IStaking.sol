// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5;

interface IStaking {
    function stake(
        address _to,
        uint256 _amount
    ) external returns (uint256);

    function claim(address _recipient, bool _rebasing) external returns (uint256);

    function forfeit() external returns (uint256);

    function toggleLock() external;

    function unstake(
        address _to,
        uint256 _amount,
        bool _trigger
    ) external returns (uint256);

    function rebase() external;

    function index() external view returns (uint256);

    function stakingSupply() external view returns (uint256);

    function setBondDepositor(address _bondDepositor) external;

    function allowExternalStaking(bool allow) external;
}

