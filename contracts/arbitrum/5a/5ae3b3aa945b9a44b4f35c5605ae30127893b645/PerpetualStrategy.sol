// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./IVault.sol";
import "./IPositionRouter.sol";
import "./IRouter.sol";

/**
 * @notice
 *  This is a GMX perpetual trading strategy contract
 *  inputs: address[3], [hypervisorAddress, indexToken, hedgeTokenAddress]
 *  config: abi.encodePacked(bytes32(referralCode))
 */
contract PerpetualStrategy {
  string public name = "gmx-perp-strategy0";
  IVault public gmxVault;
  IPositionRouter public positionRouter;
  IRouter public gmxRouter;
  address public strategist;
  mapping (address => mapping(uint256 => bool)) signal;  // mapping(tradeToken => mapping(lookback => signal));

  modifier onlyStrategist() {
    require(msg.sender == strategist, "!strategist");
    _;
  }

  constructor() {
    strategist = msg.sender;
    gmxVault = IVault(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    gmxRouter = IRouter(0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064);
    positionRouter = IPositionRouter(0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868);
  }

  function setSignal(address _tradeToken, uint256 _lookback, bool _signal) external onlyStrategist {
    signal[_tradeToken][_lookback] = _signal;
  }

  function setStrategist(address _strategist) external onlyStrategist {
    require(_strategist != address(0), "zero address");
    strategist = _strategist;
  }

  /**
   * @notice
   *  create increase position
   *  we can't interact directly with GMX vault contract because leverage was disabled by default and 
   *   can be set only by TimeLock(governance) and registered contracts. So we need to use their 
   *   peripheral contracts to do perp.
   *  this function doesn't open position actually, just register position information. Actual position
   *   opening/closing is done by a keeper of GMX vault.
   * @param indexToken the address of token to long / short
   * @param collateralToken the address of token to be used as collateral. 
   *  in long position, `collateralToken` should the same as `indexToken`.
   *  in short position, `collateralToken` should be stable coin.
   * @param amountIn: the amount of tokenIn you want to deposit as collateral
   * @param minOut: the min amount of collateralToken to swap for
   * @param sizeDelta: the USD value of the change in position size. decimals is 30
   * @param isLong: if long, true or false
   */
  function createIncreasePosition(
    address indexToken,
    address collateralToken,
    uint256 amountIn,
    uint256 minOut,
    uint256 sizeDelta,
    bool isLong
  ) external payable {
    // if (isLong == true) {
    //   require(indexToken == collateralToken, "invalid collateralToken");
    // }
    // require(msg.value >= positionRouter.minExecutionFee(), "too low execution fee");
    // require(
    //   sizeDelta > gmxVault.tokenToUsdMin(address(hedgeToken), amountIn),
    //   "too low leverage"
    // );
    // require(
    //   sizeDelta.div(gmxVault.tokenToUsdMin(address(hedgeToken), amountIn)) < gmxVault.maxLeverage().div(BASIS_POINTS_DIVISOR),
    //   "exceed max leverage"
    // );
    // // check available amounts to open positions
    // _checkPool(isLong, indexToken, collateralToken, sizeDelta);

    // /* code to check minimum open position amount in the case of first opening */
    
    // address[] memory path;
    // if (address(hedgeToken) == collateralToken) {
    //   path = new address[](1);
    //   path[0] = address(hedgeToken);
    // } else {
    //   path = new address[](2);
    //   path[0] = address(hedgeToken);
    //   path[1] = collateralToken;
    // }
    
    // uint256 priceBasisPoints = isLong ? BASIS_POINTS_DIVISOR + _slippage : BASIS_POINTS_DIVISOR - _slippage;
    // uint256 refPrice = isLong ? gmxVault.getMaxPrice(indexToken) : gmxVault.getMinPrice(indexToken);
    // uint256 acceptablePrice = refPrice.mul(priceBasisPoints).div(BASIS_POINTS_DIVISOR);
    
    // bytes32 requestKey = IPositionRouter(positionRouter).createIncreasePosition{value: msg.value}(
    //   path,
    //   indexToken,
    //   amountIn,
    //   minOut,       // it's better to provide minimum output token amount from a caller rather than calculate here
    //   sizeDelta,    // we can set sizeDelta based on leverage value. need to decide which one is preferred
    //   isLong,
    //   acceptablePrice,   // current ETH mark price, check which is more efficient between minPrice and maxPrice
    //   msg.value,
    //   _referralCode,
    //   address(this)
    // );

  }

  /**
   * @notice
   *  create decrease position
   *  we can't interact directly with GMX vault contract because leverage was disabled by default and 
   *   can be set only by TimeLock(governance) and registered contracts. So we need to use their 
   *   peripheral contracts to do perp.
   *  this function doesn't close position actually, just register position information. Actual position
   *   opening/closing is done by a keeper of GMX vault.
   * @param indexToken the address of token to long / short
   * @param collateralToken the address of token to be used as collateral. 
   *  in long position, `collateralToken` should the same as `indexToken`.
   *  in short position, `collateralToken` should be stable coin.
   * @param collateralDelta: the amount of collateral in USD value to withdraw
   * @param sizeDelta: the USD value of the change in position size. decimals is 30
   * @param isLong: if long, true or false
   * @param minOut: the min output token amount you would receive
   */
  function createDecreasePosition(
    address indexToken,
    address collateralToken,
    uint256 collateralDelta,
    uint256 sizeDelta,
    bool isLong,
    uint256 minOut
  ) public payable {
    // if (isLong == true) {
    //   require(indexToken == collateralToken, "invalid collateralToken");
    // }
    // require(msg.value >= IPositionRouter(positionRouter).minExecutionFee(), "too low execution fee");
    // // require(
    // //   sizeDelta > collateralDelta,
    // //   "too low leverage"
    // // );
    // // require(
    // //   sizeDelta.div(gmxVault.tokenToUsdMin(address(hedgeToken), amountIn)) < gmxVault.maxLeverage().div(BASIS_POINTS_DIVISOR),
    // //   "exceed max leverage"
    // // );

    // address[] memory path;
    // if (address(hedgeToken) == collateralToken) {
    //   path = new address[](1);
    //   path[0] = address(hedgeToken);
    // } else {
    //   path = new address[](2);
    //   path[0] = collateralToken;
    //   path[1] = address(hedgeToken);
    // }
    
    // uint256 priceBasisPoints = isLong ? BASIS_POINTS_DIVISOR - _slippage : BASIS_POINTS_DIVISOR + _slippage;
    // uint256 refPrice = isLong ? gmxVault.getMinPrice(indexToken) : gmxVault.getMaxPrice(indexToken);
    // uint256 acceptablePrice = refPrice.mul(priceBasisPoints).div(BASIS_POINTS_DIVISOR);
    // bytes32 requestKey = IPositionRouter(positionRouter).createDecreasePosition{value: msg.value}(
    //   path,
    //   indexToken,
    //   collateralDelta,
    //   sizeDelta,
    //   isLong,
    //   address(this),
    //   acceptablePrice,
    //   minOut,
    //   msg.value,
    //   false,
    //   address(this)
    // );

  }

  function run(bytes calldata performData) external {
    // Caller caller = Caller(msg.sender);
    // // check if caller has fund in gmx
    // // if yes,
    // bytes32 positionKey = keccak256(abi.encodePacked(
    //   caller.address,
    //   collateralToken,
    //   indexToken,
    //   isLong
    // ));
    // (uint256 size, , , , , , ) = gmxVault.positions(positionKey);
    // createDecreasePosition(indexToken, collateralToken, 0, size, isLong, minOut);
  }

  function getSignal(address _tradeToken, uint256 _lookback) external view returns (bool) {
    return signal[_tradeToken][_lookback];
  }
}

