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

import { IERC20 } from "./IERC20.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { SafeCast } from "./SafeCast.sol";
import { SafeMath } from "./SafeMath.sol";

import { IController } from "./IController.sol";
import { IIntegrationRegistry } from "./IIntegrationRegistry.sol";
import { Invoke } from "./Invoke.sol";
import { IJasperVault } from "./IJasperVault.sol";
import { IDelegatedManager } from "./IDelegatedManager.sol";
import { IGMXAdapter } from "./IGMXAdapter.sol";
import { IPositionRouterCallbackReceiver } from "./IGMXCallBack.sol";
import { IGMXReader } from "./IGMXReader.sol";
import { ModuleBase } from "./ModuleBase.sol";
import { Position } from "./Position.sol";
import { PreciseUnitMath } from "./PreciseUnitMath.sol";
import  { IGMXModule } from "./IGMXModule.sol";
import { IWETH } from "./IWETH.sol";

contract GMXModule is ModuleBase, ReentrancyGuard, IPositionRouterCallbackReceiver, IGMXModule {
  using SafeCast for int256;
  using PreciseUnitMath for uint256;
  using PreciseUnitMath for int256;

  using Position for uint256;
  using SafeMath for uint256;

  using Invoke for IJasperVault;
  using Position for IJasperVault.Position;
  using Position for IJasperVault;
  /* ============ Events ============ */

  event InCreasingPosition(
    IJasperVault _jasperVault,
    address _underlyingToken,
    address _positionToken,
    int256 _underlyingUnits,
    uint256 preActionUnderlyingNotional,
    uint256 postActionUnderlyingNotional,
    string  _integrationName,
    bytes  _positionData
  );
  event Swap(
    IJasperVault _jasperVault,
    address _tokenIn,
    address _tokenOut,
    int256 _underlyingUnits,
    uint256 preActionUnderlyingNotional,
    uint256 postActionUnderlyingNotional,
    string  _integrationName,
    bytes  _positionData
  );
  event OrderCreate(
    IJasperVault _jasperVault,
    address _underlyingToken,
    address _positionToken,
    int256 _underlyingUnits,
    uint256 preActionUnderlyingNotional,
    uint256 postActionUnderlyingNotional,
    string  _integrationName,
    bool increasing,
    bytes  _positionData
  );

  event DeCreasingPosition(
    IJasperVault _jasperVault,
    address _underlyingToken,
    address _positionToken,
    int256 _underlyingUnits,
    uint256 preActionUnderlyingNotional,
    uint256 postActionUnderlyingNotional,
    string  _integrationName,
    bytes  _positionData
  );

  /* ============ State Variables ============ */
  function weth()external override view returns(IWETH){
    return IWETH(address(0));
  }
  uint256 public immutable coinTypeIndexToken   = 11;

  struct PositionData {
    address _jasperVault;
    address _collateralToken;
    address _indexToken;
  }
  mapping(bytes => PositionData) requestKey2Position;

  /* ============ Constructor ============ */

  /*
    @param _controller               Address of controller contract

 */
  constructor(IController _controller) public ModuleBase(_controller) {

  }

  /**
   * MANAGER-ONLY: Instructs the JasperVault to Increasing Position with an underlying asset into a specified adapter.
   *
   * @param _jasperVault             Instance of the JasperVault
   * @param _underlyingToken      Address of the component to be push position
   * @param _positionToken         the address of the token you want to long or short
   * @param _underlyingUnits      Quantity of underlying units in Position units
   * @param _integrationName      Name of position module integration (mapping on integration registry)
   * @param _positionData             Arbitrary bytes to pass into the gmxAdapter
   */
  function increasingPosition(
    IJasperVault _jasperVault,
    address _underlyingToken,
    address _positionToken,
    int256 _underlyingUnits,
    string calldata _integrationName,
    bytes calldata _positionData
  )
  external
  override
  nonReentrant
  onlyManagerAndValidSet(_jasperVault)
  {
    (
    uint256 preActionUnderlyingNotional,
    uint256 postActionUnderlyingNotional
    ) =   _validateAndIncreasingPosition(
      _integrationName,
      _jasperVault,
      _underlyingToken,
      _positionToken,
      _underlyingUnits,
      _positionData
    );
    emit InCreasingPosition(
      _jasperVault,
      _underlyingToken,
      _positionToken,
      _underlyingUnits,
      preActionUnderlyingNotional,
      postActionUnderlyingNotional,
      _integrationName,
      _positionData
    );
  }
  function gmxPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease) external override {
    PositionData memory _position = requestKey2Position[abi.encodePacked(positionKey)];
    bytes memory __data;
    bytes4 FUNC_SELECTOR = bytes4(keccak256("_updatePosition(address,address,uint256,bytes)"));
    bytes memory data = abi.encodeWithSelector(FUNC_SELECTOR,IJasperVault(_position._jasperVault), _position._collateralToken, 0, __data);
    (bool success, bytes memory returnData) = address(this).call(data);
    require(success,"_updatePosition fail");

    data = abi.encodeWithSelector(FUNC_SELECTOR,IJasperVault(_position._jasperVault), _position._indexToken, coinTypeIndexToken, __data);
    ( success, returnData) = address(this).call(data);
    require(success,"_updatePosition fail");
  }

  /**
   * MANAGER-ONLY: Instructs the JasperVault to gmx Decreasing Position asset into its underlying via a specified adapter.
   *
   * @param _jasperVault             Instance of the JasperVault
     * @param _underlyingToken      Address of the underlying asset
     * @param _positionToken         Address of the component to be  Decreasing Position
     * @param _decreasingPositionUnits         Quantity of  Decreasing Position tokens in Position units
     * @param _integrationName      ID of GMX module integration (mapping on integration registry)
     * @param _positionData           Arbitrary bytes to pass into the GMXAdapter
     */
  function decreasingPosition(
    IJasperVault _jasperVault,
    address _underlyingToken,
    address _positionToken,
    int256 _decreasingPositionUnits,
    string calldata _integrationName,
    bytes calldata _positionData
  )
  external
  override
  nonReentrant
  onlyManagerAndValidSet(_jasperVault)
  {
    (
    uint256 preActionUnderlyingNotional,
    uint256 postActionUnderlyingNotional
    ) = _validateAndDecreasingPosition(
      _integrationName,
      _jasperVault,
      _underlyingToken,
      _positionToken,
      _decreasingPositionUnits,
      _positionData
    );

    emit DeCreasingPosition(
      _jasperVault,
      _underlyingToken,
      _positionToken,
      _decreasingPositionUnits,
      preActionUnderlyingNotional,
      postActionUnderlyingNotional,
      _integrationName,
      _positionData
    );
  }


  /**
   * Initializes this module to the JasperVault. Only callable by the JasperVault's manager.
   *
   * @param _jasperVault             Instance of the JasperVault to issue
     */
  function initialize(IJasperVault _jasperVault) external override onlySetManager(_jasperVault, msg.sender) {
    require(controller.isSet(address(_jasperVault)), "Must be controller-enabled JasperVault");
    require(isSetPendingInitialization(_jasperVault), "Must be pending initialization");
    _jasperVault.initializeModule();
  }

  /**
   * Removes this module from the JasperVault, via call by the JasperVault.
   */
  function removeModule() external override {}



  /**
   * The GMXModule calculates the total notional underlying to Open Increasing Position, approves the underlying to the 3rd party
   * integration contract, then invokes the JasperVault to call Increasing Position by passing its calldata along.
   * Returns notional amount of underlying tokens and positionToken.
   */
  function _validateAndIncreasingPosition(
    string calldata _integrationName,
    IJasperVault _jasperVault,
    address _underlyingToken,
    address _positionToken,
    int256 _underlyingUnits,
    bytes calldata _positionData
  )
  internal  returns (uint256, uint256)
  {
    // Snapshot pre OpenPosition balances
    uint256 preActionUnderlyingNotional = _snapshotTargetAssetsBalance(_jasperVault, _underlyingToken);

    uint256 notionalUnderlying;

    if(_underlyingUnits<0){
      notionalUnderlying=preActionUnderlyingNotional;
    }else{
      notionalUnderlying = _jasperVault.totalSupply().getDefaultTotalNotional(_underlyingUnits.abs());
    }

    IGMXAdapter gmxAdapter = IGMXAdapter(getAndValidateAdapter(_integrationName));

    _jasperVault.invokeApprove(_underlyingToken, gmxAdapter.GMXRouter(), notionalUnderlying);


    // Get function call data and invoke on JasperVault
    bytes memory data = _createIncreasingPositionCallDataAndInvoke(
      _jasperVault,
      gmxAdapter,
      _underlyingToken,
      _positionToken,
      notionalUnderlying,
      _positionData
    );
    requestKey2Position[data]._jasperVault = address(_jasperVault);
    requestKey2Position[data]._collateralToken = _underlyingToken;
    requestKey2Position[data]._indexToken = _positionToken;
    uint256 postActionUnderlyingNotional = _snapshotTargetAssetsBalance(_jasperVault, _underlyingToken);
    _updatePosition(_jasperVault, _underlyingToken, 0, _positionData);
    _updatePosition(_jasperVault, _positionToken, coinTypeIndexToken, _positionData);
    return  (preActionUnderlyingNotional, postActionUnderlyingNotional);
  }

  /**
   * The module calculates the total notional Decreasing token to GMX, then invokes the JasperVault to call
   * decreasing position by passing its calldata along.
   *
   * Returns notional amount of underlying tokens  notionalDeCreasingPosition and tokens postActionUnderlyingNotional.
   */
  function _validateAndDecreasingPosition(
    string calldata _integrationName,
    IJasperVault _jasperVault,
    address _underlyingToken,
    address _positionToken,
    int256 _positionTokenUnits,
    bytes calldata _positionData
  ) internal returns (uint256, uint256) {
    uint256 preActionUnderlyingNotional = _snapshotTargetAssetsBalance(_jasperVault, _underlyingToken);
    uint256 notionalDeCreasingPosition;
    if(_positionTokenUnits<0){
      notionalDeCreasingPosition=preActionUnderlyingNotional;
    }else{
      notionalDeCreasingPosition = _jasperVault.totalSupply().getDefaultTotalNotional(_positionTokenUnits.abs());
    }
    IGMXAdapter gmxAdapter = IGMXAdapter(getAndValidateAdapter(_integrationName));

    // Get function call data and invoke on JasperVault
    _createDecreasingPositionDataAndInvoke(
      _jasperVault,
      gmxAdapter,
      _underlyingToken,
      _positionToken,
      notionalDeCreasingPosition,
      _positionData
    );
    uint256 postActionUnderlyingNotional  = _snapshotTargetAssetsBalance(_jasperVault, _underlyingToken);
    //_collateralTokens
    _updatePosition(_jasperVault, _underlyingToken, 0, _positionData);
    _updatePosition(_jasperVault, _positionToken, coinTypeIndexToken, _positionData);
    return (
    notionalDeCreasingPosition,
    postActionUnderlyingNotional
    );
  }

  /**
   * Create the calldata for _positionData and then invoke the call on the JasperVault.
   */
  function _createIncreasingPositionCallDataAndInvoke(
    IJasperVault _jasperVault,
    IGMXAdapter _gmxAdapter,
    address _underlyingToken,
    address _positionToken,
    uint256 _notionalUnderlying,
    bytes calldata _positionData
  ) internal returns(bytes memory){
    (
    address callTarget,
    uint256 callValue,
    bytes memory callByteData
    ) = _gmxAdapter.getInCreasingPositionCallData(
      _underlyingToken,
      _positionToken,
      _notionalUnderlying,
      address(_jasperVault),
      _positionData
    );

    return _jasperVault.invoke(callTarget, callValue, callByteData);
  }

  /**
   * Create the calldata for gmx decreasing position and then invoke the call on the JasperVault.
   */
  function _createDecreasingPositionDataAndInvoke(
    IJasperVault _jasperVault,
    IGMXAdapter _gmxAdapter,
    address _underlyingToken,
    address _positionToken,
    uint256 _notionalUnderlying,
    bytes calldata _positionData
  ) internal  {
    (
    address callTarget,
    uint256 callValue,
    bytes memory callByteData
    ) = _gmxAdapter.getDeCreasingPositionCallData(
      _underlyingToken,
      _positionToken,
      _notionalUnderlying,
      address(_jasperVault),
      _positionData
    );

     _jasperVault.invoke(callTarget, callValue, callByteData);
  }

  function _updatePositionModuleAndCoinType( IJasperVault _jasperVault,address _token,address module,uint256 coinType) internal{
    _jasperVault.editExternalPositionCoinType(_token, address(this), coinType);
    if (!_jasperVault.isExternalPositionModule(_token, address(this))) {
      _jasperVault.addExternalPositionModule(_token, address(this));
    }
  }
  function _updatePositionByBalance(
    IJasperVault _jasperVault,
    string calldata _integrationName,
    address _token) public {
    require(IDelegatedManager(_jasperVault.manager()).owner() == msg.sender,"only _jasperVault Owner");
    IGMXAdapter gmxAdapter = IGMXAdapter(getAndValidateAdapter(_integrationName));
    uint256 tokenBalance = gmxAdapter.getTokenBalance(_token, address(_jasperVault));
    _jasperVault.editDefaultPosition(_token, tokenBalance.mul(1 ether).div(_jasperVault.totalSupply()));
  }

  /**
   * Take snapshot of JasperVault's balance of  tokens.
   */
  function _snapshotTargetAssetsBalance(
    IJasperVault _jasperVault,
    address _underlyingToken
  ) internal view returns(uint256) {
    return IERC20(_underlyingToken).balanceOf(address(_jasperVault));
  }

  function toBytes(bytes32 _data) public pure returns (bytes memory) {
    return abi.encodePacked(_data);
  }

  /**
  *
  * @param _jasperVault             Instance of the JasperVault
   * @param _tokenIn      Address of the component to be swap
   * @param _tokenOut         the address of the token you want to long or short
   * @param _underlyingUnits      Quantity of underlying units in Position units
   * @param _integrationName      Name of position module integration (mapping on integration registry)
   * @param _positionData             Arbitrary bytes to pass into the gmxAdapter
   */
  function swap(
    IJasperVault _jasperVault,
    address _tokenIn,
    address _tokenOut,
    int256 _underlyingUnits,
    string calldata _integrationName,
    bytes calldata _positionData
  )
  external
  override
  nonReentrant
  onlyManagerAndValidSet(_jasperVault)
  {
    (
    uint256 preActionUnderlyingNotional,
    uint256 postActionUnderlyingNotional
    ) =   _validateAndSwap(
      _integrationName,
      _jasperVault,
      _tokenIn,
      _tokenOut,
      _underlyingUnits,
      _positionData
    );
    emit Swap(
      _jasperVault,
      _tokenIn,
      _tokenOut,
      _underlyingUnits,
      preActionUnderlyingNotional,
      postActionUnderlyingNotional,
      _integrationName,
      _positionData
    );
  }


  /**
   * The GMXModule calculates the total notional underlying to Open Increasing Position, approves the underlying to the 3rd party
   * integration contract, then invokes the JasperVault to call Increasing Position by passing its calldata along.
   * Returns notional amount of underlying tokens and positionToken.
   */
  function _validateAndSwap(
    string calldata _integrationName,
    IJasperVault _jasperVault,
    address _tokenIn,
    address _tokenOut,
    int256 _underlyingUnits,
    bytes calldata _positionData
  )
  internal  returns (uint256, uint256)
  {
    // Snapshot pre OpenPosition balances
    uint256 preActionUnderlyingNotional = _snapshotTargetAssetsBalance(_jasperVault, _tokenIn);
    uint256 notionalUnderlying;
    if(_underlyingUnits<0){
      notionalUnderlying=preActionUnderlyingNotional;
    }else{
      notionalUnderlying = _jasperVault.totalSupply().getDefaultTotalNotional(_underlyingUnits.abs());
    }
    IGMXAdapter gmxAdapter = IGMXAdapter(getAndValidateAdapter(_integrationName));
    _jasperVault.invokeApprove(_tokenIn, gmxAdapter.GMXRouter(), notionalUnderlying);
    // Get function call data and invoke on JasperVault
    bytes memory data = _createSwapCallDataAndInvoke(_jasperVault,  gmxAdapter, _positionData );

    uint256 postActionUnderlyingNotional = _snapshotTargetAssetsBalance(_jasperVault, _tokenIn);
    _updatePosition(_jasperVault, _tokenIn, 0, _positionData);
    _updatePosition(_jasperVault, _tokenOut, 0, _positionData);
    return  (preActionUnderlyingNotional, postActionUnderlyingNotional);
  }




    /**
   * Create the calldata for _positionData and then invoke the call on the JasperVault.
   */
  function _createSwapCallDataAndInvoke(
    IJasperVault _jasperVault,
    IGMXAdapter _gmxAdapter,
    bytes calldata _data
  ) internal returns(bytes memory){
    (
    address callTarget,
    uint256 callValue,
    bytes memory callByteData
    ) = _gmxAdapter.getSwapCallData(_data);
    return _jasperVault.invoke(callTarget, msg.value, callByteData);
  }

  /**
  *
  * @param _jasperVault           Instance of the JasperVault
   * @param _underlyingToken      Address of the component to be createOrder
   * @param _indexToken           The address of the token you want to long or short
   * @param _underlyingUnits      Quantity of underlying units in Position units
   * @param _integrationName      Name of position module integration (mapping on integration registry)
   * @param _positionData         Arbitrary bytes to pass into the gmxAdapter
   */
  function creatOrder(
    IJasperVault _jasperVault,
    address _underlyingToken,
    address _indexToken,
    int256 _underlyingUnits,
    string calldata _integrationName,
    bool _isLong,
    bytes calldata _positionData
  )
  external
  override
  nonReentrant
  onlyManagerAndValidSet(_jasperVault)
  {
    (
    uint256 preActionUnderlyingNotional,
    uint256 postActionUnderlyingNotional
    ) =   _validateAndCreateOrder(
      _integrationName,
      _jasperVault,
      _underlyingToken,
      _indexToken,
      _underlyingUnits,
      _isLong,
      _positionData
    );
    emit OrderCreate(
      _jasperVault,
      _underlyingToken,
      _indexToken,
      _underlyingUnits,
      preActionUnderlyingNotional,
      postActionUnderlyingNotional,
      _integrationName,
      _isLong,
      _positionData
    );
  }
  /**
 * The GMXModule calculates the total notional underlying to Open Increasing Position, approves the underlying to the 3rd party
 * integration contract, then invokes the JasperVault to call Increasing Position by passing its calldata along.
 * Returns notional amount of underlying tokens and positionToken.
 */
  function _validateAndCreateOrder(
    string calldata _integrationName,
    IJasperVault _jasperVault,
    address _underlyingToken,
    address _indexToken,
    int256 _underlyingUnits,
    bool _isLong,
    bytes calldata _positionData
  )
  internal  returns (uint256, uint256)
  {
    // Snapshot pre OpenPosition balances
    uint256 preActionUnderlyingNotional = _snapshotTargetAssetsBalance(_jasperVault, _underlyingToken).mul(1 ether).div(_jasperVault.totalSupply());
    uint256 notionalUnderlying;
    if(_underlyingUnits<0){
      notionalUnderlying=preActionUnderlyingNotional;
    }else{
      notionalUnderlying = _jasperVault.totalSupply().getDefaultTotalNotional(_underlyingUnits.abs());
    }
    IGMXAdapter gmxAdapter = IGMXAdapter(getAndValidateAdapter(_integrationName));
    if (_isLong) {
      _jasperVault.invokeApprove(_underlyingToken, gmxAdapter.GMXRouter(), notionalUnderlying);
    }

    // Get function call data and invoke on JasperVault
    bytes memory data = _createOrderCallDataAndInvoke(_jasperVault,  gmxAdapter, _isLong, _positionData );

    uint256 postActionUnderlyingNotional = _snapshotTargetAssetsBalance(_jasperVault, _underlyingToken);
    _updatePosition(_jasperVault, _underlyingToken, 0, _positionData);
    _updatePosition(_jasperVault, _indexToken, 0, _positionData);
    return  (preActionUnderlyingNotional, postActionUnderlyingNotional);
  }

  /**
 * Create the calldata for _positionData and then invoke the call on the JasperVault.
 */
  function _createOrderCallDataAndInvoke(
    IJasperVault _jasperVault,
    IGMXAdapter _gmxAdapter,
    bool _isLong,
    bytes calldata _data
  ) internal returns(bytes memory){

    if (_isLong ){
      (address callTarget,
      uint256 callValue,
      bytes memory callByteData
      ) = _gmxAdapter.getCreateIncreaseOrderCallData(_data);
      return _jasperVault.invoke(callTarget, msg.value, callByteData);
   }else{
      (address callTarget,
      uint256 callValue,
      bytes memory callByteData
      ) = _gmxAdapter.getCreateDecreaseOrderCallData(_data);
      return _jasperVault.invoke(callTarget, msg.value, callByteData);
    }
  }

  /**
   * edit position with new token
   */
  function _updatePosition(
    IJasperVault _jasperVault,
    address _token,
    uint256 coinType,
    bytes calldata _data
  ) internal {

    // set data
    if (_data.length != 0){
      _jasperVault.editExternalPositionData(_token, address(this), _data);
    }

    if (coinType!=0){
        uint256 externalUnit =  getGMXPositionTotalUnit(_jasperVault, _token);
        _updatePositionModuleAndCoinType(_jasperVault, _token, address(this), coinType);
        _jasperVault.editExternalPositionUnit(_token, address(this), int256(externalUnit));
    }
    uint256 tokenBalance = IERC20(_token).balanceOf(address(_jasperVault));
    uint256 newTokenUnit = tokenBalance.mul(1 ether).div(_jasperVault.totalSupply());
    _jasperVault.editDefaultPosition(_token, newTokenUnit);


  }


  function getGMXPositionTotalUnit(IJasperVault _jasperVault, address _indexToken)internal returns(uint256) {
    address usdcAddr = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address[] memory _collateralTokens = new address[](1);
    _collateralTokens[0] = usdcAddr;
    address[] memory _indexTokens = new address[](1);
    _indexTokens[0] = _indexToken;
    bool[] memory _isLong = new bool[](1);
    uint256[] memory _IncreasingGMXPosition =  IGMXReader(0x22199a49A999c351eF7927602CFB187ec3cae489).getPositions(0x489ee077994B6658eAfA855C308275EAd8097C4A, address(_jasperVault), _collateralTokens, _indexTokens, _isLong);
    _isLong[0] = true;
    uint256[] memory _DecreasingGMXPosition =  IGMXReader(0x22199a49A999c351eF7927602CFB187ec3cae489).getPositions(0x489ee077994B6658eAfA855C308275EAd8097C4A, address(_jasperVault), _collateralTokens, _indexTokens, _isLong);
    return _IncreasingGMXPosition[0]+_DecreasingGMXPosition[0];
}
}

