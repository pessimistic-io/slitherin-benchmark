// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IWombatPool {

    function deposit(
        address token,
        uint256 amount,
        uint256 minimumLiquidity,
        address to,
        uint256 deadline,
        bool shouldStake
    ) external;

    function withdraw(
        address token,
        uint256 liquidity,
        uint256 minimumAmount,
        address to,
        uint256 deadline
    ) external;
    
    function addressOfAsset(address token)
        external
        view
        returns (address asset);
    
    function quotePotentialDeposit(address token, uint256 amount)
        external
        view
        returns (uint256 liquidity, uint256 reward);
    
    function quotePotentialWithdraw(address token, uint256 liquidity)
        external
        view
        returns (uint256 amount, uint256 fee);
}
