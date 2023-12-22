//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IERC20Metadata as IERC20} from "./IERC20Metadata.sol";
import "./IERC165.sol";

import {PositionId, MoneyMarket} from "./libraries_DataTypes.sol";

interface IMoneyMarket is IERC165 {
    function NEEDS_ACCOUNT() external view returns (bool);

    function moneyMarketId() external view returns (MoneyMarket);

    function initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) external;

    function lend(PositionId positionId, IERC20 asset, uint256 amount) external returns (uint256 actualAmount);

    function withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to)
        external
        returns (uint256 actualAmount);

    function borrow(PositionId positionId, IERC20 asset, uint256 amount, address to)
        external
        returns (uint256 actualAmount);

    function repay(PositionId positionId, IERC20 asset, uint256 amount) external returns (uint256 actualAmount);

    function claimRewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset, address to) external;

    function collateralBalance(PositionId positionId, IERC20 asset) external returns (uint256 balance);
}

