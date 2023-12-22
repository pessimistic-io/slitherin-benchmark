// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.9;
pragma abicoder v2;

import "./Math.sol";
import "./IGrid.sol";
import "./IGridStructs.sol";
import "./IGridParameters.sol";
import "./IGridFactory.sol";
import "./GridAddress.sol";
import "./CallbackValidator.sol";
import "./BoundaryMath.sol";
import "./IMakerOrderManager.sol";
import "./Multicall.sol";
import "./AbstractPayments.sol";
import "./AbstractSelfPermit2612.sol";
import {Draco} from "./Draco.sol";


/// @title The implementation for the maker order manager
contract MakerOrderManager is
    IMakerOrderManager,
    AbstractPayments,
    AbstractSelfPermit2612,
    Multicall
{
   // @dev The address of token
    address public immutable draco;
   // @dev The address of token
    address public immutable swapAddress;
    // @dev The address of token
    address public immutable quoterAddress;
    constructor(address _gridFactory, address _weth9,address _draco,address _swapAddress,address _quoterAddress) AbstractPayments(_gridFactory, _weth9) {
        draco = _draco;
        swapAddress = _swapAddress;
        quoterAddress = _quoterAddress;
    }


    struct PlaceMakerOrderCalldata {
        GridAddress.GridKey gridKey;
        address payer;
    }

    /// @inheritdoc IGridPlaceMakerOrderCallback
    function gridexPlaceMakerOrderCallback(uint256 amount0, uint256 amount1, bytes calldata data) external override {
        PlaceMakerOrderCalldata memory decodeData = abi.decode(data, (PlaceMakerOrderCalldata));
        CallbackValidator.validate(gridFactory, decodeData.gridKey);

        if (amount0 > 0) pay(decodeData.gridKey.token0, decodeData.payer, _msgSender(), amount0);

        if (amount1 > 0) pay(decodeData.gridKey.token1, decodeData.payer, _msgSender(), amount1);
    }

    /// @inheritdoc IMakerOrderManager
    function initialize(InitializeParameters calldata parameters) external payable {
        GridAddress.GridKey memory gridKey = GridAddress.gridKey(
            parameters.tokenA,
            parameters.tokenB,
            parameters.resolution
        );
        address grid = GridAddress.computeAddress(gridFactory, gridKey);

        address recipient = parameters.recipient == address(0) ? _msgSender() : parameters.recipient;

        IGrid(grid).initialize(
            IGridParameters.InitializeParameters({
                priceX96: parameters.priceX96,
                recipient: recipient,
                orders0: parameters.orders0,
                orders1: parameters.orders1
            }),
            abi.encode(PlaceMakerOrderCalldata({gridKey: gridKey, payer: _msgSender()}))
        );
    }

    /// @inheritdoc IMakerOrderManager
    function placeMakerOrder(
        PlaceOrderParameters calldata parameters
    ) external payable checkDeadline(parameters.deadline) returns (uint256 orderId) {
        GridAddress.GridKey memory gridKey = GridAddress.gridKey(
            parameters.tokenA,
            parameters.tokenB,
            parameters.resolution
        );
        address grid = GridAddress.computeAddress(gridFactory, gridKey);

        address recipient = parameters.recipient == address(0) ? _msgSender() : parameters.recipient;
        // sell tax 
        bool hasTax = (parameters.zero && gridKey.token0 == draco) || (!parameters.zero && gridKey.token1 == draco) ;
        uint256 totalTax ;
        if(hasTax){
            // charge tax to le grid for temp ,when order not filled ,tax will back
           totalTax =  Draco(draco).tempChargeTax(_msgSender(),parameters.amount);
        }
        uint128 _totalTax = uint128(totalTax);
        orderId = _placeMakerOrder(
            grid,
            gridKey,
            recipient,
            parameters.zero,
            parameters.boundaryLower,
            parameters.amount - _totalTax
        );
    }

    function _placeMakerOrder(
        address grid,
        GridAddress.GridKey memory gridKey,
        address recipient,
        bool zero,
        int24 boundaryLower,
        uint128 amount
    ) private returns (uint256 orderId) {
        orderId = IGrid(grid).placeMakerOrder(
            IGridParameters.PlaceOrderParameters({
                recipient: recipient,
                zero: zero,
                boundaryLower: boundaryLower,
                amount: amount
            }),
            abi.encode(PlaceMakerOrderCalldata({gridKey: gridKey, payer: _msgSender()}))
        );
    }
    function settleMakerOrderAndCollectInBatch(
        address grid,
        address recipient,
        uint256[] memory orderIds,
        bool unwrapWETH9
    ) external override  returns (uint128 amount0Total, uint128 amount1Total) {
        //the orders makerOutAmount
        uint128 totalMakerAmount ;
        //the orders been taked out amount for back the tax
        uint128 totalMakerAmountOut ;
        
        for (uint256 i = 0; i < orderIds.length; i++) {
            (uint64 bundleId,address owner,uint128 amount) = IGrid(grid).orders(orderIds[i]);

           ( ,bool zero,,,,)  = IGrid(grid).bundles(bundleId);

             // G_COO: caller is not the order owner
             require(owner == _msgSender(), "G_COO");

            ( uint128 amount0,uint128 amount1 ) = IGrid(grid).settleMakerOrderAndCollect(recipient,orderIds[i],unwrapWETH9);

            if(zero && IGrid(grid).token0() == draco ){
                totalMakerAmountOut += amount0;
                totalMakerAmount += amount;
              } else if(!zero && IGrid(grid).token1() == draco ){
               totalMakerAmountOut += amount1;
               totalMakerAmount += amount;
            }  
            amount0Total += amount0;
            amount1Total += amount1;
        }
        if( totalMakerAmountOut > 0){
           Draco(draco).backTax(recipient,totalMakerAmountOut,totalMakerAmount-totalMakerAmountOut);
        }
    }

    
}

