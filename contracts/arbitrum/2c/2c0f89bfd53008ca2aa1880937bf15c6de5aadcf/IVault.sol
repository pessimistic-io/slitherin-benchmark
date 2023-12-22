// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./IStrategy.sol";

interface IVault {
    event Deposited(
        address indexed user,
        address indexed beneficiary,
        uint256 amount,
        uint256 share,
        uint256 fee
    );
    event Withdrawn(
        address indexed user,
        address indexed beneficiary,
        uint256 amount,
        uint256 share,
        uint256 fee
    );
    event Rebalanced(address indexed strategy, int256 amount);
    event StrategySet(address indexed strategy);
    event TreasurySet(address indexed treasury);

    function deposit(uint256 amount, address beneficiary) external;

    function withdraw(uint256 amount, address beneficiary) external;

    function rebalance(bool onlyInvest) external;

    function totalBalance() external view returns (uint256);

    function underlying() external view returns (IERC20);

    function strategy() external view returns (IStrategy);

    function treasury() external view returns (address);
}

