// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BetDetails, WagerTokenDetails } from "./Structs.sol";

interface IPepeBet {
    function placeBet(
        address user,
        address asset,
        address betToken,
        uint256 amount,
        uint256 openingPrice,
        uint256 runTime,
        bool isLong
    ) external;

    function settleBet(uint256 betID, uint256 closingPrice) external;

    function deposit(uint256 amount, address token) external;

    function withdraw(uint256 amount, address token) external;

    function pause() external;

    function unPause() external;

    function modifyFee(uint16 newFee) external;

    function modifyMinAndMaxBetRunTime(uint16 _minRunTime, uint16 _maxRunTime) external;

    function setLiquidityPool(address _liquidityPool) external;

    function updateOracle(address _oracle) external;

    function approveWagerTokens(WagerTokenDetails[] calldata tokenDetails_) external;

    function revokeWagerTokens(address[] calldata tokens_) external;

    function updateWagerTokenDetails(address tokenAddress, uint256 _maxBetAmount, uint256 _minBetAmount) external;

    function approveAssets(address[] calldata newAssets) external;

    function unapproveAssets(address[] calldata assets) external;

    function modifyLeverage(uint16 newLeverage) external;

    function updateFeeTaker(address newFeeTaker) external;

    function liquidityPool() external returns (address);

    function feeTaker() external returns (address);

    function oracle() external returns (address);

    function betId() external returns (uint256);

    function fee() external returns (uint16);

    function leverage() external returns (uint16);

    function minRunTime() external returns (uint16);

    function maxRunTime() external returns (uint16);
}

