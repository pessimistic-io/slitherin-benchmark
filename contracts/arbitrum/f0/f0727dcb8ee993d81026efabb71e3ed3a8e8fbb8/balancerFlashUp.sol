// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {IPool} from "./IPool.sol";
import {ISwapRouter} from "./ISwapRouter.sol";

import "./IVault.sol";
import "./IFlashLoanRecipient.sol";

contract FlashUpRecipient is IFlashLoanRecipient {
    // Flashloan leverage creator - intended for use with a specific python application

    IVault private constant vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    event Swap(
      address fromToken,
      address toToken,
      uint256 amountFrom,
      uint256 amountTo,

      // Fee incurred at every step of the swap path
      uint256[] fees,

      // tokens sold at every step of the swap path
      address[] sellTokens);


    struct FlashUpParams {
        address lendAsset;
        address borrowAsset;
        address uniAddr;
        address onBehalfOf;
        uint256 transferAmt;
        uint256 lendAmount; 
        uint256 borrowAmt;
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

    function getBalance(address _tokenAddress) external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    function withdraw(address _tokenAddress) external onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

     function averageIn(address collateralAsset,
                        address debtAsset,
                        uint256 amount,
                        ISwapRouter.ExactInputSingleParams[] memory swapParams,
                        address uniAddr,
                        bool swapFirst) public returns (bool) {
        // Average into a leveraged position by depositing more collateral

         uint256 supAmt = amount;
         // Optionally swap debtToken holdings into the collateral before depositing (a true average-in ie a purchase)
         if(swapFirst) {
             IERC20(debtAsset).transferFrom(msg.sender, address(this), swapParams[0].amountIn);
             this.multihopSwap(swapParams, uniAddr, false); // ISwapRouter(flashUpParams.uniAddr).exactInputSingle(swapParams[0]);
             supAmt = this.getBalance(collateralAsset);
         }
         // Otherwise, deposit existing collateralToken holdings into position
         else {
           IERC20(collateralAsset).transferFrom(msg.sender, address(this), supAmt);
         }
        uint256 debtBal = this.getBalance(debtAsset);
        // In case we swapped and the swap was malformed ie. we didn't trade the entire transferFrom
        // (not necessary for collateral token - we ensured that the entire collateral balance of the contract is supplied on behalf of the user)
        if(debtBal > 0) {
            IERC20(debtAsset).transfer(msg.sender, debtBal);
        }
         IERC20(collateralAsset).approve(address(POOL), supAmt);
         POOL.supply(collateralAsset, supAmt, msg.sender, 0);
       return true;
     }


    function requestFlashLoan(FlashUpParams memory flashUpParams,
                              ISwapRouter.ExactInputSingleParams[] memory swapParams,
                              ISwapRouter.ExactInputSingleParams[] memory swapFirstParams,
                              bool swapFirst) public {
        // Enter into a leveraged position
        bytes memory params = abi.encode(flashUpParams, swapParams, swapFirstParams, swapFirst);
        IERC20[] memory tokens = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);

        // Flashloan exactly the amount of collateral you'll end up with
        tokens[0] = IERC20(flashUpParams.lendAsset);
        amounts[0] = flashUpParams.lendAmount;
        vault.flashLoan(this, tokens, amounts, params);
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        // Execute flashloan leverage 

        require(msg.sender == address(vault));
        address asset = address(tokens[0]);
        ISwapRouter.ExactInputSingleParams[] memory swapParams;
        ISwapRouter.ExactInputSingleParams[] memory swapFirstParams;
        FlashUpParams memory flashUpParams;
        bool swapFirst;
        (flashUpParams, swapParams, swapFirstParams, swapFirst) = abi.decode(userData, (FlashUpParams, ISwapRouter.ExactInputSingleParams[], ISwapRouter.ExactInputSingleParams[], bool));
        
        // Instantiate balance of capital to cover flashloan difference
        if(flashUpParams.transferAmt != 0 && !swapFirst) {
            IERC20(asset).transferFrom(flashUpParams.onBehalfOf, address(this), flashUpParams.transferAmt);
        }
        // Optionally gain exposure before levering up (as opposed to levering up on existing holdings)
        if(swapFirst) {
            IERC20(flashUpParams.borrowAsset).transferFrom(flashUpParams.onBehalfOf, address(this), swapFirstParams[0].amountIn);
            this.multihopSwap(swapFirstParams, flashUpParams.uniAddr, false); // ISwapRouter(flashUpParams.uniAddr).exactInputSingle(swapParams[0]);       
        }

        IERC20(flashUpParams.borrowAsset).approve(flashUpParams.uniAddr, flashUpParams.borrowAmt);
        IERC20(asset).approve(address(POOL), flashUpParams.lendAmount);
        // Lend flashloaned asset (maintaining transferAmt - lendAmt balance)
        POOL.supply(asset, flashUpParams.lendAmount, flashUpParams.onBehalfOf, 0); 
        // Borrow against the new collateral
        POOL.borrow(flashUpParams.borrowAsset, flashUpParams.borrowAmt, 2, 0, flashUpParams.onBehalfOf);
        // Swap borrow token back to loan token - balance should now be sufficient to pay back loan
        this.multihopSwap(swapParams, flashUpParams.uniAddr, false);

        //Repay flashloan with fee
        require(amounts[0] + feeAmounts[0] <= this.getBalance(asset), 'Insufficient balance to repay flashloan!');
        IERC20(asset).transfer(address(vault), amounts[0] + feeAmounts[0]);

        // Ensure all balances are given back to the user
        uint256 leftOver = this.getBalance(asset);
        if(leftOver != 0) {
            IERC20(asset).transfer(flashUpParams.onBehalfOf, leftOver);
        }
        leftOver = this.getBalance(flashUpParams.borrowAsset);
        if(leftOver != 0) {
            IERC20(flashUpParams.borrowAsset).transfer(flashUpParams.onBehalfOf, leftOver);
        }
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only the contract owner can call this function"
        );
        _;
    }
}
