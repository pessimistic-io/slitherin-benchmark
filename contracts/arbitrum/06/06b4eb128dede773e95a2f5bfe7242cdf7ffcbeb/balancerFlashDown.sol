// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {IPool} from "./IPool.sol";
import {ISwapRouter} from "./ISwapRouter.sol";

import "./IVault.sol";
import "./IFlashLoanRecipient.sol";

contract FlashDownRecipient is IFlashLoanRecipient {
    // Flashloan leverage remover - intended for use with a specific python application

    IVault private constant vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

event Swap(
      address fromToken,
      address toToken,
      uint256 amountFrom,
      uint256 amountTo,
      uint256[] fees,
      address[] sellTokens);


   struct FlashDownParams {
        address lendAsset;
        address borrowAsset;
        address uniAddr;
        address aTokenAddr;
        address onBehalfOf;
        uint256 withdrawAmt;
        uint256 repayAmt;
    }   
    
    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    IPool public immutable POOL;
    address payable owner;

    constructor(address _addressProvider)
    {
        ADDRESSES_PROVIDER = IPoolAddressesProvider(_addressProvider);
        POOL = IPool(ADDRESSES_PROVIDER.getPool());
        owner = payable(msg.sender);
    }
    
    function multihopSwap(ISwapRouter.ExactInputSingleParams[] memory swapParams, address routerAddress, bool swapOnly) public {
        // Execute a series of swaps on uniswap - assumes that each swap's tokenIn is the previous swap's tokenOut
        uint256 amountOut;
        uint256 amountIn = swapParams[0].amountIn;
        address tokenIn = swapParams[0].tokenIn;
        address tokenOut = swapParams[swapParams.length - 1].tokenOut;
        uint256[] memory fees = new uint256[](swapParams.length);
        address[] memory sellTokens = new address[](swapParams.length);

        // if being called directly (and not during a leverage transaction), first call transferFrom 
        // otherwise, the contract should already have the requisite swap balances
        if(swapOnly) {
            IERC20(swapParams[0].tokenIn).transferFrom(msg.sender, address(this), swapParams[0].amountIn);
        }
        for(uint i=0; i < swapParams.length; i++) {
            sellTokens[i] = swapParams[i].tokenIn;
            fees[i] = swapParams[i].amountIn * swapParams[i].fee / 1000000;
            IERC20(swapParams[i].tokenIn).approve(routerAddress, swapParams[i].amountIn);
            amountOut = ISwapRouter(routerAddress).exactInputSingle(swapParams[i]);
            if(i != swapParams.length - 1) {
                swapParams[i+1].amountIn = amountOut;
            }
        }
        emit Swap(tokenIn, tokenOut, amountIn, amountOut, fees, sellTokens);
        // Transfer back to user for a direct call (we're done)
        if(swapOnly) {
            IERC20(swapParams[swapParams.length-1].tokenOut).transfer(msg.sender, amountOut);
        }
    }

    function averageOut(address aToken,
                         address collateralAsset,
                         address debtAsset,
                         uint256 amount,
                         ISwapRouter.ExactInputSingleParams[] memory swapParams,
                         address uniAddr,
                         bool swapAfter) public returns (bool) {
       // Average out of a leveraged position by withdrawing collateral                
       IERC20(aToken).transferFrom(msg.sender, address(this), amount);
       POOL.withdraw(collateralAsset, amount, address(this));

       // Optionally swap collateral back to debt (a true average out ie a sale)
       if(swapAfter) {
         this.multihopSwap(swapParams, uniAddr, false);
       }

       // Ensure all holdings are transferred back to user 
       // we either need to give user back their collateralToken or the debtToken we swapped into
       uint256 debtBal = this.getBalance(debtAsset);
       uint256 collatBal = this.getBalance(collateralAsset);
       if(debtBal > 0) {
          IERC20(debtAsset).transfer(msg.sender, debtBal);
       }
       if(collatBal > 0) {
          IERC20(collateralAsset).transfer(msg.sender, collatBal);
       }
       return true;
     }
    function requestFlashLoan(FlashDownParams calldata flashDownParams,
                             ISwapRouter.ExactInputSingleParams[] calldata swapParams,
                             ISwapRouter.ExactInputSingleParams[] calldata swapAfterParams,
                             bool swapAfter) public {
        bytes memory params = abi.encode(flashDownParams, swapParams, swapAfterParams, swapAfter);
        IERC20[] memory tokens = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        // Flashloan exactly the amount of debt to be repaid
        tokens[0] = IERC20(flashDownParams.borrowAsset);
        amounts[0] = flashDownParams.repayAmt;
        vault.flashLoan(this, tokens, amounts, params);
    }

     function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        // Execute flashloan leverage
        ISwapRouter.ExactInputSingleParams[] memory swapParams;
        ISwapRouter.ExactInputSingleParams[] memory swapAfterParams;

        FlashDownParams memory flashDownParams;
        bool swapAfter;
        (flashDownParams, swapParams, swapAfterParams, swapAfter) = abi.decode(userData, (FlashDownParams, ISwapRouter.ExactInputSingleParams[], ISwapRouter.ExactInputSingleParams[], bool));
    
     
        IERC20(flashDownParams.borrowAsset).approve(address(POOL), amounts[0]);

        // Repay position debt with flashloaned amount
        POOL.repay(flashDownParams.borrowAsset, amounts[0], 2, flashDownParams.onBehalfOf); 
        // Grab user's aTokens
        IERC20(flashDownParams.aTokenAddr).transferFrom(flashDownParams.onBehalfOf, address(this), flashDownParams.withdrawAmt);
        // Withdraw them
        POOL.withdraw(flashDownParams.lendAsset, flashDownParams.withdrawAmt, address(this));
        // Convert them back to debtToken to repay flashloan
        this.multihopSwap(swapParams, flashDownParams.uniAddr, false);
        //Repay Loan with fee
        require(amounts[0] + feeAmounts[0] <= this.getBalance(flashDownParams.borrowAsset), 'Insufficient balance to repay flashloan!');
        IERC20(flashDownParams.borrowAsset).transfer(address(vault), amounts[0] + feeAmounts[0]);

        // Optionally swap collateralToken back to debtToken (a true close - remove exposure, not just leverage)
        if(swapAfter) {
            this.multihopSwap(swapAfterParams, flashDownParams.uniAddr, false);
        }
        
        // Ensure all balances are given back to the user
        uint256 leftOver = this.getBalance(flashDownParams.lendAsset);
        if(leftOver != 0) {
            IERC20(flashDownParams.lendAsset).transfer(flashDownParams.onBehalfOf, leftOver);
        }
        leftOver = this.getBalance(flashDownParams.borrowAsset);
        if(leftOver != 0) {
            IERC20(flashDownParams.borrowAsset).transfer(flashDownParams.onBehalfOf, leftOver);
        }
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only the contract owner can call this function"
        );
        _;
    }
    function getBalance(address _tokenAddress) external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }
}
