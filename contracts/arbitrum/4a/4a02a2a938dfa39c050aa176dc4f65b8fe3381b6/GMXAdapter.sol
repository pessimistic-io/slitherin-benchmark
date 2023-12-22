/*
    Copyright 2021 Set Labs Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.6.10;
pragma experimental "ABIEncoderV2";

import {IGMXAdapter} from "./IGMXAdapter.sol";
import {IGMXRouter} from "./IGMXRouter.sol";
import {IGMXOrderBook} from "./IGMXOrderBook.sol";
import {IJasperVault} from "./IJasperVault.sol";
import {Invoke} from "./Invoke.sol";
import {Ownable} from "./Ownable.sol";
import { IERC20 } from "./IERC20.sol";

/**
 * @title GMXAdapter
 * GMX adapter for GMX that returns data for (opening/increasing position)/(closing/decreasing position) of tokens
 */
contract GMXAdapter is Ownable {
  struct SwapData {
  address[]  _path;
  uint256 _amountIn;
  uint256 _minOut;
  uint256 _swapType;
  address _receiver;
  }
  struct IncreaseOrderData {
  address[]  _path;
  uint256 _amountIn;
  address _indexToken;
  uint256 _minOut;
  uint256 _sizeDelta;
  address _collateralToken;
  bool _isLong;
  uint256 _triggerPrice;
  bool _triggerAboveThreshold;
  uint256 _executionFee;
  bool _shouldWrap;
  }
  struct DecreaseOrderData {
  address _indexToken;
  uint256 _sizeDelta;
  address _collateralToken;
  uint256 _collateralDelta;
  bool _isLong;
  uint256 _triggerPrice;
  bool _triggerAboveThreshold;
  }
  struct IncreasePositionRequest {
  address[] _path;
  address _indexToken;
  uint256 _amountIn;
  uint256 _minOut;
  uint256 _sizeDelta;
  bool _isLong;
  uint256 _acceptablePrice;
  uint256 _executionFee;
  bytes32 _referralCode;
  address _callbackTarget;
  address jasperVault;
  }
  struct DecreasePositionRequest {
  address[] _path;
  address _indexToken;
  uint256 _collateralDelta;
  uint256 _sizeDelta;
  bool _isLong;
  address _receiver;
  uint256 _acceptablePrice;
  uint256 _minOut;
  uint256 _executionFee;
  bool _withdrawETH;
  address _callbackTarget;
  }

    using Invoke for IJasperVault;
    address public   PositionRouter;
    address public  GMXRouter;
    address public  ETH_TOKEN;
    address public  OrderBook;
    address public  Vault;
    mapping(address=>bool) whiteList;
    enum SwapType {SwapToken, SwapTokensToETH, SwapETHToTokens} // 枚举
    /* ============ Constructor ============ */
    constructor(address _positionRouter, address _GMXRouter, address _OrderBook, address _Vault, address[] memory _whiteList) public {
        for (uint i; i<_whiteList.length;i++){
          whiteList[_whiteList[i]]=true;
        }
        //Address of Curve Eth/StEth stableswap pool.
        PositionRouter = _positionRouter;
        GMXRouter = _GMXRouter;
        OrderBook = _OrderBook;
        Vault = _Vault;
    }

    /* ============ External Functions ============ */
    function updateWhiteList(address[] calldata _addList, address[] calldata removeList) public {
      for (uint i; i<_addList.length;i++){
        whiteList[_addList[i]]=true;
      }
      for (uint i; i<removeList.length;i++){
        whiteList[removeList[i]]=false;
      }
    }
    function approvePositionRouter()external view  returns (address, uint256, bytes memory) {
      bytes memory approveCallData = abi.encodeWithSignature(
        "approvePlugin(address)",
        PositionRouter
      );
      return (GMXRouter, 0, approveCallData);
    }
    /**
     * Generates the calldata to increasing position asset into its underlying.
     *
     * @param _collateralToken    Address of the _collateralToken asset
     * @param _indexToken         Address of the component to be _index
     * @param _underlyingUnits    Total quantity of _collateralToken
     * @param _to                 Address to send the asset tokens to
     * @param _positionData       Data of position
     *
     * @return address              Target contract address
     * @return uint256              Total quantity of decreasing token units to position. This will always be 215000000000000 for increasing position
     * @return bytes                position calldata
     */

    function getInCreasingPositionCallData(
        address _collateralToken,
        address _indexToken,
        uint256 _underlyingUnits,
        address _to,
        bytes calldata _positionData
    ) external view  returns (address, uint256, bytes memory) {
        IncreasePositionRequest memory request = abi.decode(
            _positionData,
            (IncreasePositionRequest)
        );

        if (
            !IGMXRouter(GMXRouter).approvedPlugins(
                request.jasperVault,
                PositionRouter
            )
        ) {
            bytes memory approveCallData = abi.encodeWithSignature(
                "approvePlugin(address)",
                PositionRouter
            );
            return (GMXRouter, 0, approveCallData);
        }
        require(whiteList[request._indexToken],"_indexToken not in whiteList");
        for (uint i;i< request._path.length;i++){
          require(whiteList[request._path[i]],"_path not in whiteList");
        }
        bytes memory callData = abi.encodeWithSignature(
            "createIncreasePosition(address[],address,uint256,uint256,uint256,bool,uint256,uint256,bytes32,address)",
            request._path,
            request._indexToken,
            request._amountIn,
            request._minOut,
            request._sizeDelta,
            request._isLong,
            request._acceptablePrice,
            request._executionFee,
            request._referralCode,
            request._callbackTarget
        );

        return (PositionRouter, request._executionFee, callData);
    }

    /**
     * Generates the calldata to decreasing position asset into its underlying.
     *
     * @param _underlyingToken    Address of the underlying asset
     * @param _indexToken         Address of the component to be _index
     * @param _indexTokenUnits    Total quantity of _index
     * @param _to                 Address to send the asset tokens to
     * @param _positionData       Data of position
     *
     * @return address              Target contract address
     * @return uint256              Total quantity of decreasing token units to position. This will always be 215000000000000 for decreasing
     * @return bytes                position calldata
     */
    function getDeCreasingPositionCallData(
        address _underlyingToken,
        address _indexToken,
        uint256 _indexTokenUnits,
        address _to,
        bytes calldata _positionData
    ) external view  returns (address, uint256, bytes memory) {
        DecreasePositionRequest memory request = abi.decode(
            _positionData,
            (DecreasePositionRequest)
        );
      require(whiteList[request._indexToken],"_indexToken not in whiteList");
      for (uint i;i< request._path.length;i++){
        require(whiteList[request._path[i]],"_path not in whiteList");
      }
        bytes memory callData = abi.encodeWithSignature(
            "createDecreasePosition(address[],address,uint256,uint256,bool,address,uint256,uint256,uint256,bool,address)",
            request._path,
            request._indexToken,
            request._collateralDelta,
            request._sizeDelta,
            request._isLong,
            request._receiver,
            request._acceptablePrice,
            request._minOut,
            request._executionFee,
            request._withdrawETH,
            request._callbackTarget
        );

        return (PositionRouter, request._executionFee, callData);
    }


    function IsApprovedPlugins(address _Vault)public returns(bool){
      return IGMXRouter(GMXRouter).approvedPlugins(_Vault, PositionRouter);
    }
    /**
    * Generates the calldata to swap asset.
    * @param _swapData       Data of _swapData
    *
    * @return address        Target contract address
    * @return uint256        Total quantity of decreasing token units to position. This will always be 215000000000000 for decreasing
    * @return bytes          Position calldata
    **/
    function getSwapCallData( bytes calldata _swapData )external view   returns (address, uint256, bytes memory) {
      SwapData memory data = abi.decode(_swapData, (SwapData));
      for (uint i;i< data._path.length;i++){
        require(whiteList[data._path[i]],"_path not in whiteList");
      }
      bytes memory callData;
      if (data._swapType == uint256(SwapType.SwapToken) ){
        callData = abi.encodeWithSelector(IGMXRouter.swap.selector, data._path, data._amountIn, data._minOut, data._receiver);
        return (GMXRouter, 0, callData);
      }else if(data._swapType ==  uint256(SwapType.SwapTokensToETH) ){
        callData = abi.encodeWithSelector(IGMXRouter.swapTokensToETH.selector, data._path, data._amountIn, data._minOut, data._receiver);
        return (GMXRouter, 0, callData);
      }else  if(data._swapType ==  uint256(SwapType.SwapETHToTokens) ){
        callData = abi.encodeWithSelector(IGMXRouter.swapETHToTokens.selector, data._path, data._minOut, data._receiver);
        return (GMXRouter, data._amountIn, callData);
      }
      return (GMXRouter, 0, callData);
    }
    /**
      * Generates the calldata to Create IncreaseOrder CallData .
      * @param _data       Data of order
      *
      * @return address        Target contract address
      * @return uint256        Call data value
      * @return bytes          Order Calldata
    **/
    function getCreateIncreaseOrderCallData( bytes calldata _data)external view   returns (address, uint256, bytes memory){

      IncreaseOrderData memory data = abi.decode(_data, (IncreaseOrderData));

      require(whiteList[data._indexToken],"_indexToken not in whiteList");
      for (uint i;i< data._path.length;i++){
        require(whiteList[data._path[i]],"_path not in whiteList");
      }
      bytes memory callData = abi.encodeWithSelector(
      IGMXOrderBook.createIncreaseOrder.selector,
      data._amountIn,
      data._indexToken,
      data._minOut,
      data._sizeDelta,
      data._collateralToken,
      data._isLong,
      data._triggerPrice,
      data._triggerAboveThreshold,
      data._executionFee,
      data._shouldWrap);
      return (OrderBook, 300001000000000, callData);
    }
    /**
      * Generates the calldata to Create Decrease Order CallData .
      * @param _data       Data of order
      *
      * @return address        Target contract address
      * @return uint256        Call data value
      * @return bytes          Order Calldata
    **/
    function getCreateDecreaseOrderCallData(
      bytes calldata _data
    )external view   returns (address, uint256, bytes memory){
      DecreaseOrderData memory data = abi.decode(_data, (DecreaseOrderData));
      require(whiteList[data._indexToken],"_indexToken not in whiteList");

      bytes memory callData = abi.encodeWithSelector(IGMXOrderBook.createDecreaseOrder.selector,
       data._indexToken,
       data._sizeDelta,
       data._collateralToken,
       data._collateralDelta,
       data._isLong,
       data._triggerPrice,
       data._triggerAboveThreshold
      );
      return (OrderBook, 300001000000000, callData);
    }
    function getTokenBalance(address _token, address _jasperVault)external view returns(uint256){
      require(whiteList[_token],"token not in whiteList");
      return IERC20(_token).balanceOf(_jasperVault);
    }
}

