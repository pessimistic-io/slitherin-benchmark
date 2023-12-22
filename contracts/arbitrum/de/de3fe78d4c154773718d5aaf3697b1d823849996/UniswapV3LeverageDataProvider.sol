// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import {IERC20} from "./ERC20_IERC20.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {TickMath} from "./TickMath.sol";
import {UniswapV3Position} from "./UniswapV3Position.sol";
import {IUniswapV3DataProvider} from "./IUniswapV3DataProvider.sol";
import {IUniswapV3LeverageDataProvider} from "./IUniswapV3LeverageDataProvider.sol";
import {UniswapV3LeveragedPosition} from "./UniswapV3LeveragedPosition.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {IPool} from "./IPool.sol";

contract UniswapV3LeverageDataProvider is IUniswapV3LeverageDataProvider {
    IUniswapV3DataProvider public immutable uniswapV3DataProvider;

    constructor(IUniswapV3DataProvider _uniswapV3DataProvider) {
        uniswapV3DataProvider = _uniswapV3DataProvider;
    }

    function getPositionData(address position) public view returns (PositionData memory) {
        uint256 tokenId = UniswapV3LeveragedPosition(position).positionTokenId();
        IUniswapV3DataProvider.PositionData memory positionData = uniswapV3DataProvider.getPositionData(tokenId);
        address debtAsset = UniswapV3LeveragedPosition(position).borrowedToken();
        IPoolAddressesProvider addressesProvider = UniswapV3LeveragedPosition(position).addressesProvider();
        IPool pool = IPool(addressesProvider.getPool());
        uint256 debt = IERC20(pool.getReserveData(debtAsset).variableDebtTokenAddress).balanceOf(position);

        return PositionData({uniswapV3Position: positionData, debt: debt, debtAsset: debtAsset});
    }

    function getPositionsData(address[] memory positions) public view returns (PositionData[] memory datas) {
        datas = new PositionData[](positions.length);
        for (uint256 i = 0; i < positions.length; i++) {
            datas[i] = getPositionData(positions[i]);
        }
    }
}

