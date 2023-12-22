// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { ISwapSimulator } from "./ISwapSimulator.sol";
import { IClearingHouse } from "./IClearingHouse.sol";
import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";

interface IBaseVault {
    event PriceInfo(uint256 assetPriceX128);

    function rebalance() external;

    function closeTokenPosition() external;

    function ethPoolId() external view returns (uint32);

    function depositCap() external view returns (uint256);

    function rageAccountNo() external view returns (uint256);

    function rageVPool() external view returns (IUniswapV3Pool);

    function swapSimulator() external view returns (ISwapSimulator);

    function rageClearingHouse() external view returns (IClearingHouse);
}

