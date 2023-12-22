// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./IMainPoolToken.sol";


interface IMainPool is IERC20 {

    struct TokenConfiguration {
        address token;
        uint256 weight;
        IMainPoolToken tokenConnector;
    }

    struct PoolConfiguration {
        address stable;
        TokenConfiguration[] tokenConfigurations;
    }

    struct FeeConfiguration {
        address treasury;
        uint256 joinFee;
        uint256 exitFee;
    }

    struct TokenPriorityIdConfiguration {
        uint256 id;
        address token;
    }

    event Joined(address indexed caller, address indexed tokenIn, uint256 amountIn, uint256 mintAmount, uint256 joinFeeAmount);
    event Exited(address indexed caller, uint256 amountIn, uint256 amountOut, uint256 exitFeeAmount);
    event PoolConfigurationUpdated(PoolConfiguration configuration);
    event FeeConfigurationUpdated(FeeConfiguration configuration);

    function mainPoolOwner() external view returns (address);
    function deposit(address tokenIn, uint256 amountIn, uint256 mintAmountOut) external returns (uint256 mintAmount);
    function withdraw(uint256 amountIn, uint256 minAmountOut) external returns (uint256 amountOut);
    function refill() external returns (uint256);
    function deplete() external returns (uint256);
    
    function rebalance() external returns (bool);

    function makeWithdrawRequest(uint256 shares) external returns (bool);
    function cancelWithdrawRequest(uint256 shares, uint256 unlockEpoch) external returns (bool);

    function updatePoolConfiguration(PoolConfiguration memory configuration_) external returns (bool);
    function updateFeeConfiguration(FeeConfiguration memory configuration_) external returns (bool);
}

