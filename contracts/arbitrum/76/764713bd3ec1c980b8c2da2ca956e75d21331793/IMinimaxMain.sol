// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./IPoolAdapter.sol";
import "./IPriceOracle.sol";
import "./IMarket.sol";

interface IMinimaxMain {
    function getUserFeeAmount(address user, uint stakeAmount) external view returns (uint);

    function oneInchRouter() external view returns (address);

    function market() external view returns (IMarket);

    function priceOracles(IERC20Upgradeable) external view returns (IPriceOracle);

    function getPoolAdapterSafe(address pool) external view returns (IPoolAdapter);

    function poolAdapters(uint256 pool) external view returns (IPoolAdapter);

    function busdAddress() external view returns (address);

    function emitPositionWasModified(uint positionIndex) external;

    function emitPositionWasCreated(
        uint positionIndex,
        IERC20Upgradeable token,
        uint price
    ) external;

    function emitPositionWasClosed(
        uint positionIndex,
        IERC20Upgradeable token,
        uint price
    ) external;

    function emitPositionWasLiquidated(
        uint positionIndex,
        IERC20Upgradeable token,
        uint price
    ) external;

    function emitStakedBaseTokenWithdraw(
        uint positionIndex,
        address token,
        uint amount
    ) external;

    function emitStakedSwapTokenWithdraw(
        uint positionIndex,
        address token,
        uint amount
    ) external;

    function emitRewardTokenWithdraw(
        uint positionIndex,
        address token,
        uint amount
    ) external;

    function closePosition(uint positionIndex) external;

    function disabled() external view returns (bool);
}

