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
    //logic added here
    (address collateralAsset,
    address user, 
    uint256 amountCollateral,
    uint256 amountToBorrow,
    uint24 fee
    ) = abi.decode(
      params,
      (address, address, uint256, uint256, uint24)
    );

    uint256 amountOwed = amount + premium;

    //approve to the mahalend contract
    IERC20(debtAsset).approve(address(mahalend), type(uint256).max);

    
    //supply 0.1 weth to mahalend
    mahalend.supply(debtAsset, amount, user, 0);

    
    //borrow 0.5 usdc from mahalend
    mahalend.borrow(collateralAsset, amountToBorrow, 2, 0, user);

    //approve to the swap func
    IERC20(collateralAsset).approve(address(swap), type(uint256).max);

    ISwapRouter.ExactOutputSingleParams memory swapParams = ISwapRouter.ExactOutputSingleParams({
      tokenIn: collateralAsset,
      tokenOut: debtAsset,
      fee: fee,
      recipient: address(this),
      deadline: block.timestamp,
      amountOut:amountOwed,
      amountInMaximum: IERC20(collateralAsset).balanceOf(address(this)),
      sqrtPriceLimitX96: 0
    });
    
    swap.exactOutputSingle(swapParams);

    
    // then repay the loan with the below code.
    IERC20(debtAsset).approve(address(POOL), amountOwed);

    return true;
  }

  function requestETHLong(
    address _debtAsset,
    uint256 _amountDebt,
    address _collateralAsset,
    uint256 _amountCollateral,
    uint256 _amountToBorrow,
    address _userAddress,
    uint24 _fee
  ) public {
    address receiverAddress = address(this);
    address asset = _debtAsset;
    uint256 amountCollateral = _amountCollateral;
    uint256 loanAmount = _amountDebt;
    uint16 referralCode = 0;   

    bytes memory params = abi.encode(_collateralAsset, _userAddress, amountCollateral, _amountToBorrow, _fee);

    IERC20(_collateralAsset).transferFrom(
            _userAddress,
            receiverAddress,
            amountCollateral
        );

    // take flashloan of the debt
    POOL.flashLoanSimple(receiverAddress, asset, loanAmount, params, referralCode);

    // send the profits to the caller to be done.
    IERC20(asset).transfer(
      _userAddress,
      IERC20(asset).balanceOf(address(this))
    );

    IERC20(_collateralAsset).transfer(
      _userAddress,
      IERC20(_collateralAsset).balanceOf(address(this))
    );
  }

  function getBalance(address _tokenAddress) external view returns (uint256) {
    return IERC20(_tokenAddress).balanceOf(address(this));
  }
}

