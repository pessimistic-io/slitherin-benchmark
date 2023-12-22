// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import { FlashLoanSimpleReceiverBase } from "./FlashLoanSimpleReceiverBase.sol";
import { IPoolAddressesProvider } from "./IPoolAddressesProvider.sol";
import { IPool } from "./IPool.sol";
import { IERC20 } from "./IERC20.sol";

import { ISwapRouter } from "./ISwapRouter.sol";
import {ILeverageHelper} from "./ILeverageHelper.sol";

contract SingleAssetETHLong is FlashLoanSimpleReceiverBase {
  address payable owner;
  IPool public mahalend;
  ISwapRouter public swap;

  constructor(
    address _addressProvider,
    address _mahalendAddress,
    address _UniSwapAddress
  ) FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider)) {
    owner = payable(msg.sender);
    mahalend = IPool(_mahalendAddress);
    swap = ISwapRouter(_UniSwapAddress);
  }

  function executeOperation(
    address debtAsset,
    uint256 amount,
    uint256 premium,
    address initiator,
    bytes calldata params
  ) external override returns (bool) {
    (address collateralAsset,
    uint256 mahalendAmount,
    uint24 fee,
    uint positionFlag,
    address collateralDebtTokenAddress
    ) = abi.decode(
      params,
      (address, uint256, uint24, uint, address)
    );

    IERC20(debtAsset).approve(address(mahalend), type(uint256).max);

    //if flag is 0 then it's open position else it is close position
    if(positionFlag == 0){
        
    mahalend.supply(debtAsset, amount, initiator, 0);

    mahalend.borrow(collateralAsset, mahalendAmount, 2, 0, initiator);

    } else {
    
    mahalend.repay(debtAsset, amount,2, initiator);

    IERC20(collateralDebtTokenAddress).transferFrom(
      initiator,
      address(this),
      mahalendAmount
    );
    
    mahalend.withdraw(collateralAsset, mahalendAmount, address(this));
    }

    IERC20(collateralAsset).approve(address(swap), type(uint256).max);

    ISwapRouter.ExactOutputSingleParams memory swapParams = ISwapRouter.ExactOutputSingleParams({
      tokenIn: collateralAsset,
      tokenOut: debtAsset,
      fee: fee,
      recipient: address(this),
      deadline: block.timestamp,
      amountOut:amount + premium,
      amountInMaximum: IERC20(collateralAsset).balanceOf(address(this)),
      sqrtPriceLimitX96: 0
    });
    
    swap.exactOutputSingle(swapParams);

    IERC20(debtAsset).approve(address(POOL), amount + premium);

    return true;
  }

  function requestOpenETHLong(
    address _debtAsset,
    uint256 _amountDebt,
    address _collateralAsset,
    uint256 _amountCollateral,
    uint256 _amountToBorrow,
    uint24 _fee
  ) public {

    bytes memory params = abi.encode(_collateralAsset, _amountToBorrow, _fee, 0, 0x0);

    IERC20(_collateralAsset).transferFrom(
            msg.sender,
            address(this),
            _amountCollateral
        );

    POOL.flashLoanSimple(address(this), _debtAsset, _amountDebt, params, 0);

    IERC20(_debtAsset).transfer(
      msg.sender,
      IERC20(_debtAsset).balanceOf(address(this))
    );
  }

  function getBalance(address _tokenAddress) external view returns (uint256) {
    return IERC20(_tokenAddress).balanceOf(address(this));
  }

   function requestCloseETHLong(
    address _closingDebtAsset,
    address _collateralAsset,
    uint256 _amountToWithdraw,
    uint24 _fee,
    address _variableDebtTokenAddress,
    address _collateralDebtTokenAddress
  ) public {

    bytes memory params = abi.encode(_collateralAsset, msg.sender, _amountToWithdraw, _fee, 1, _collateralDebtTokenAddress);

    POOL.flashLoanSimple(address(this), _closingDebtAsset, IERC20(_variableDebtTokenAddress).balanceOf(msg.sender), params, 0);

    IERC20(_closingDebtAsset).transfer(
      msg.sender,
      IERC20(_closingDebtAsset).balanceOf(address(this))
    );
  }
}

