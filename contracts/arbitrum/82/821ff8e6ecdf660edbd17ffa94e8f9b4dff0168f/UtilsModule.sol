/*
    Copyright 2020 Set Labs Inc.

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

pragma solidity ^0.6.10;
pragma experimental "ABIEncoderV2";

import { IController } from "./IController.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { ModuleBase } from "./ModuleBase.sol";
import { Invoke } from "./Invoke.sol";
import { IJasperVault } from "./IJasperVault.sol";
import { ModuleBase } from "./ModuleBase.sol";

import { IAToken } from "./IAToken.sol";
import { ILendingPool } from "./ILendingPool.sol";
import { IFlashLoanReceiver } from "./IFlashLoanReceiver.sol";
import { IERC20 } from "./IERC20.sol";
import { PreciseUnitMath } from "./PreciseUnitMath.sol";
import {SafeERC20} from "./SafeERC20.sol";
contract UtilsModule is ModuleBase, ReentrancyGuard,IFlashLoanReceiver{
   using PreciseUnitMath for int256;
   using SafeERC20 for IERC20;
   uint256 internal constant BORROW_RATE_MODE = 2;
   ILendingPool public lendingPool;
   address public uniswapRouter; 
   uint256 public positionMultiplier=10 ** 18;
   struct ParamInfo{
       uint256 optionType;    //1.reBalance    2.reset
       uint256 protocolType;  //1 aave  2 compound 
       IJasperVault  target;
       IJasperVault  jasperVault;
       int256 totalSupply;
       int256 ratio;
       address masterToken;
       address[]  flashLoanAssets;//flashLoan
       uint256[]  flashLoanAmounts;//flashLoan
       uint256[]  flashLoanModes;//flashLoan
       uint256 flashLoanLen;//flashLoan
       uint256 flashLoanIndex;
       address[]  handleAaveAssets;
       uint256[]  handleAaveAmounts;
       uint256 handleAaveLen;
       uint256 handleAaveIndex;
       address[]  handleAssets;//
       uint256[]  handleAmounts;//
       uint256   handleIndex;
       uint256  handleLen;

   }


   constructor(IController _controller, ILendingPool _lendingPool,address _uniswapRouter) public ModuleBase(_controller) {
        lendingPool=_lendingPool;
        uniswapRouter=_uniswapRouter;
   }

    function initialize(
        IJasperVault _jasperVault
    )
        external
    {
        _jasperVault.initializeModule();
    }


   function reset(IJasperVault _jasperVault) external nonReentrant onlyManagerAndValidSet(_jasperVault){
        int256 totalSupply=int256(_jasperVault.totalSupply());
        require(totalSupply>0,"totalSupply must greater than zero");
        address masterToken=_jasperVault.masterToken();
         ParamInfo memory param;
         param.target=_jasperVault;
         param.jasperVault=_jasperVault;
         param.totalSupply=totalSupply;
         param.masterToken=masterToken;
         param.optionType=2;
         param.protocolType=1;
        _reset(param);
   }  

   function rebalance(IJasperVault _target,IJasperVault _jasperVault,uint256 _ratio) external nonReentrant onlyManagerAndValidSet(_jasperVault){   
         int256 totalSupply=int256(_jasperVault.totalSupply());
         require(totalSupply>0,"totalSupply must greater than zero");
         address masterToken=_jasperVault.masterToken();
         ParamInfo memory param;
         param.target=_target;
         param.jasperVault=_jasperVault;
         param.ratio=int256(_ratio);
         param.totalSupply=totalSupply;
         param.masterToken=masterToken;
         param.optionType=1;
         param.protocolType=1;
        _rebalance(param);
   }


   //reset assets
   function _reset(ParamInfo memory param) internal {
       IJasperVault.Position[] memory  positions=param.jasperVault.getPositions();
       //get length
       for(uint256 i=0;i<positions.length;i++){ 
           if(positions[i].positionState==1&&positions[i].coinType==1){
                param.flashLoanLen++;
           }         
           if(positions[i].positionState==0&&positions[i].coinType==1){
                param.handleAaveLen++;
           }          
           if(positions[i].positionState==0&&positions[i].coinType==0){
                param.handleLen++;
           }                   
       }
       param.flashLoanAssets=new address[](param.flashLoanLen);
       param.flashLoanAmounts=new uint256[](param.flashLoanLen);
       param.flashLoanModes=new uint256[](param.flashLoanLen);

       param.handleAaveAssets=new address[](param.handleAaveLen);
       param.handleAssets=new address[](param.handleLen);

       for(uint256 i=0;i<positions.length;i++){ 
           if(positions[i].positionState==1&&positions[i].coinType==1){
               _updateExternalPosition(param.jasperVault,positions[i].component,positions[i].module,0,1);
               //handle data
               param.flashLoanAssets[param.flashLoanIndex]=positions[i].component;
               address dToken=BORROW_RATE_MODE==2?lendingPool.getReserveData(positions[i].component).variableDebtTokenAddress:lendingPool.getReserveData(positions[i].component).stableDebtTokenAddress;
               param.flashLoanAmounts[param.flashLoanIndex]=IERC20(dToken).balanceOf(address(param.jasperVault));
               param.flashLoanModes[param.flashLoanIndex]=0;
               param.flashLoanIndex++;
           }
           if(positions[i].positionState==0&&positions[i].coinType==1){
               _updatePosition(param.jasperVault,positions[i].component,0,1);
               param.handleAaveAssets[param.handleAaveIndex]=IAToken(positions[i].component).UNDERLYING_ASSET_ADDRESS();
               param.handleAaveIndex++;
           }        
           if(positions[i].positionState==0&&positions[i].coinType==0){
                param.handleAssets[param.handleIndex]=positions[i].component;       
                if(positions[i].component!=param.masterToken){    
                    _updatePosition(param.jasperVault,positions[i].component,0,0);
                }    
               param.handleIndex++;    
           }   
       }   
      bytes memory params=abi.encode(param);
      //is flashLoan
      if(param.flashLoanAssets.length>0){
        lendingPool.flashLoan(address(this), param.flashLoanAssets,param.flashLoanAmounts,param.flashLoanModes,address(this),params,0);
      }else{
        _afterresetToken(param,param.flashLoanAssets,param.flashLoanAmounts,param.flashLoanAmounts);
      }

   }  




   

   function _afterresetAave(       
        ParamInfo memory param,
        address[] memory assets,
        uint[] memory amounts,
        uint[] memory /*premiums*/)  internal{
            address _callContract;
            uint256  _callValue;
            bytes memory _callByteData;
            uint256 balance;
            for (uint i = 0; i < assets.length; i++) {
              param.jasperVault.invokeApprove(assets[i],address(lendingPool),amounts[i]);
              (_callContract, _callValue, _callByteData)= getAaveRepayCallData(assets[i],uint256(-1),address(param.jasperVault));
              param.jasperVault.invoke(_callContract, _callValue, _callByteData);
            }

            for(uint i=0;i<param.handleAaveAssets.length;i++){
               (_callContract,_callValue,_callByteData)= getAaveWithdrawCallData(param.handleAaveAssets[i],type(uint).max,address(param.jasperVault));
                param.jasperVault.invoke(_callContract, _callValue, _callByteData);
                 if(param.handleAaveAssets[i]!=param.masterToken){
                    balance=IERC20(param.handleAaveAssets[i]).balanceOf(address(param.jasperVault));
                    param.jasperVault.invokeApprove(param.handleAaveAssets[i],uniswapRouter,balance); 
                    (_callContract,_callValue,_callByteData)=getUniswapTokenCallData(param.handleAaveAssets[i],param.masterToken,balance,0,address(param.jasperVault));
                    param.jasperVault.invoke(_callContract, _callValue, _callByteData);
                 }
            }
   }
   function _afterresetToken(      
        ParamInfo memory param,
        address[] memory assets,
        uint[] memory amounts,
        uint[] memory premiums) internal{
            address _callContract;
            uint256  _callValue;
            bytes memory _callByteData;
            uint256 balance;

            for(uint256 i=0;i<param.handleAssets.length;i++){
                balance=IERC20(param.handleAssets[i]).balanceOf(address(param.jasperVault));
                if(balance>0&&param.handleAssets[i]!=param.masterToken){
                    param.jasperVault.invokeApprove(param.handleAssets[i],uniswapRouter,balance);                    
                    (_callContract,_callValue,_callByteData)=getUniswapTokenCallData(param.handleAssets[i],param.masterToken,balance,0,address(param.jasperVault));
                    param.jasperVault.invoke(_callContract, _callValue, _callByteData);
                }
            }
            if(assets.length>0){
                balance=IERC20(param.masterToken).balanceOf(address(param.jasperVault));
                param.jasperVault.invokeApprove(param.masterToken,uniswapRouter,balance);
                for(uint i = 0; i < assets.length; i++){
                    if(assets[i]!=param.masterToken){
                        uint256 amountOwing = amounts[i]+premiums[i];
                        if(amountOwing-balance>0){
                            (_callContract,_callValue,_callByteData)=getUniswapExactTokenCallData(param.masterToken,assets[i],amountOwing,balance,address(param.jasperVault));
                            param.jasperVault.invoke(_callContract, _callValue, _callByteData); 
                        }
                    }

                }   
            }
            balance=IERC20(param.masterToken).balanceOf(address(param.jasperVault));
            balance=uint256(int256(balance).preciseDiv(param.totalSupply));
            _updatePosition(param.jasperVault,param.masterToken,balance,0);

   }

   // 1%=1e16  100%=1e18
    function _rebalance(ParamInfo memory param) internal {
       IJasperVault.Position[] memory  positions=param.target.getPositions();
       require(positions.length==1 && positions[0].component == param.masterToken,"jasperVault not reset");
       for(uint256 i=0;i<positions.length;i++){ 
           if(positions[i].positionState==0&&positions[i].coinType==1){
                param.flashLoanLen++;
           }     
           if(positions[i].positionState==1&&positions[i].coinType==1){
                param.handleAaveLen++;
           }      
            if(positions[i].positionState==0&&positions[i].coinType==0){
                param.handleLen++;
           }                
       }
       param.flashLoanAssets=new address[](param.flashLoanLen);
       param.flashLoanAmounts=new uint256[](param.flashLoanLen);
       param.flashLoanModes=new uint256[](param.flashLoanLen);

       param.handleAaveAssets=new address[](param.handleAaveLen);
       param.handleAaveAmounts=new uint256[](param.handleAaveLen);

       param.handleAssets=new address[](param.handleLen);
       param.handleAmounts=new uint256[](param.handleLen);

       for(uint256 i=0;i<positions.length;i++){ 
           if(positions[i].positionState==0&&positions[i].coinType==1){
               param.flashLoanAssets[param.flashLoanIndex]=IAToken(positions[i].component).UNDERLYING_ASSET_ADDRESS();
               int256 newUnit=param.ratio.preciseMul(positions[i].unit);         
               param.flashLoanAmounts[param.flashLoanIndex]=uint256(newUnit.preciseMul(param.totalSupply));
               param.flashLoanModes[param.flashLoanIndex]=0;
               param.flashLoanIndex++;
               _updatePosition(param.jasperVault,positions[i].component,uint256(newUnit),1);
              
           }         

          if(positions[i].positionState==1&&positions[i].coinType==1){
               param.handleAaveAssets[param.handleAaveIndex]=positions[i].component;
               int256 newUnit=param.ratio.preciseMul(int256(positions[i].unit.abs()));
               param.handleAaveAmounts[param.handleAaveIndex]=uint256(newUnit.preciseMul(param.totalSupply));
               param.handleAaveIndex++;
               _updateExternalPosition(param.jasperVault,positions[i].component,positions[i].module,newUnit.neg(),1);
    
           }   
           if(positions[i].positionState==0&&positions[i].coinType==0){       
                int256 newUnit=param.ratio.preciseMul(positions[i].unit);
                param.handleAssets[param.handleIndex]=positions[i].component;       
                param.handleAmounts[param.handleIndex]=uint256(newUnit.preciseMul(param.totalSupply));
                param.handleIndex++;
                if(positions[i].component!=param.masterToken){
                    _updatePosition(param.jasperVault,positions[i].component,uint256(newUnit),0);
                }                
           }
       }   
      bytes memory params=abi.encode(param);
      if(param.flashLoanAssets.length>0){
        lendingPool.flashLoan(address(this), param.flashLoanAssets,param.flashLoanAmounts,param.flashLoanModes,address(this),params,0);
      }else{
         _afterRebalanceToken(param,param.flashLoanAssets,param.flashLoanAmounts,param.flashLoanAmounts);
      }

    } 
    function executeOperation(
        address[] calldata assets,
        uint[] calldata amounts,
        uint[] calldata premiums,
        address /*initiator*/,
        bytes calldata params
    ) external override returns (bool) {   
         (ParamInfo memory param)= abi.decode(params,(ParamInfo)); 
         for(uint256 i=0;i<assets.length;i++){
              IERC20(assets[i]).safeTransfer(address(param.jasperVault),amounts[i]);
         }
        if(param.optionType==1){
            _afterRebalanceAave(param,assets,amounts,premiums);
            _afterRebalanceToken(param,assets,amounts,premiums);
        }
        if(param.optionType==2){
            _afterresetAave(param,assets,amounts,premiums);
            _afterresetToken(param,assets,amounts,premiums);
        }     

        for(uint256 i=0;i<assets.length;i++){
             param.jasperVault.invokeTransfer(assets[i],address(this),(amounts[i]+premiums[i]));
        }
        for (uint i = 0; i < assets.length; i++) {
            IERC20(assets[i]).approve(address(lendingPool),(amounts[i]+premiums[i]));
        }
        // repay Aave
        return true;      
    }

    function _afterRebalanceAave(
        ParamInfo memory param,
        address[] memory assets,
        uint[] memory amounts,
        uint[] memory /*premiums*/
        ) internal {
            address _callContract;
            uint256  _callValue;
            bytes memory _callByteData;
            for (uint i = 0; i < assets.length; i++) {
              param.jasperVault.invokeApprove(assets[i],address(lendingPool),amounts[i]);
              (_callContract, _callValue, _callByteData)= getAaveDepositCallData(assets[i],amounts[i],address(param.jasperVault));
              param.jasperVault.invoke(_callContract, _callValue, _callByteData);
            }
            for(uint i=0;i<param.handleAaveAssets.length;i++){
               (_callContract,_callValue,_callByteData)= getAaveBorrowCallData(param.handleAaveAssets[i],param.handleAaveAmounts[i],address(param.jasperVault));
                param.jasperVault.invoke(_callContract, _callValue, _callByteData);
                 if(param.handleAaveAssets[i]!=param.masterToken){
                    param.jasperVault.invokeApprove(param.handleAaveAssets[i],uniswapRouter,param.handleAaveAmounts[i]); 
                    (_callContract,_callValue,_callByteData)=getUniswapTokenCallData(param.handleAaveAssets[i],param.masterToken,param.handleAaveAmounts[i],0,address(param.jasperVault));
                    param.jasperVault.invoke(_callContract, _callValue, _callByteData);
                 }

            }
    }

    function _afterRebalanceToken(
        ParamInfo memory param,        
        address[] memory assets,
        uint[] memory amounts,
        uint[] memory premiums) internal {
            address _callContract;
            uint256  _callValue;
            bytes memory _callByteData;
            uint256 balance=IERC20(param.masterToken).balanceOf(address(param.jasperVault));
            param.jasperVault.invokeApprove(param.masterToken,uniswapRouter,balance);           
            for(uint256 i=0;i<param.handleAssets.length;i++){
                 if(param.handleAssets[i]!=param.masterToken){
                    (_callContract,_callValue,_callByteData)=getUniswapExactTokenCallData(param.masterToken,param.handleAssets[i], param.handleAmounts[i],balance,address(param.jasperVault));
                    param.jasperVault.invoke(_callContract, _callValue, _callByteData); 
                 }           
            }

            if(assets.length>0){ 
                for(uint i = 0; i < assets.length; i++){
                    if(assets[i]!=param.masterToken){
                        uint256 amountOwing = amounts[i]+premiums[i];
                        (_callContract,_callValue,_callByteData)=getUniswapExactTokenCallData(param.masterToken,assets[i],amountOwing,balance,address(param.jasperVault));
                        param.jasperVault.invoke(_callContract, _callValue, _callByteData); 
                    }

                }
            }
            balance=IERC20(param.masterToken).balanceOf(address(param.jasperVault));
            balance=uint256(int256(balance).preciseDiv(param.totalSupply));
            _updatePosition(param.jasperVault,param.masterToken,balance,0);
    }
    function getAaveDepositCallData(
        address _asset,
        uint256 _amount,
        address _onBehalfOf
        ) internal view  returns (address, uint256, bytes memory){
            bytes memory callData = abi.encodeWithSignature(
                 "deposit(address,uint256,address,uint16)",
                 _asset,
                 _amount,
                 _onBehalfOf,
                 0
            );
            return (address(lendingPool), 0, callData);
    }
    function getAaveBorrowCallData(
        address _asset,
        uint256 _amount,
        address _onBehalfOf
       ) internal view  returns (address, uint256, bytes memory){
            bytes memory callData = abi.encodeWithSignature(
                 "borrow(address,uint256,uint256,uint16,address)",
                  _asset,
                  _amount,     
                  BORROW_RATE_MODE,
                  0,
                  _onBehalfOf     
            );           
            
            return (address(lendingPool), 0, callData);
         
    }
    function getAaveRepayCallData(address _assset,uint256 _amount,address _onBehalfOf) internal view  returns (address, uint256, bytes memory) {
            bytes memory callData = abi.encodeWithSignature(
                 "repay(address,uint256,uint256,address)",
                  _assset,
                  _amount,     
                  BORROW_RATE_MODE,
                  _onBehalfOf     
            );           
            
            return (address(lendingPool), 0, callData);
    }
    function getAaveWithdrawCallData(address _asset,uint256 _amount,address _to) internal view  returns (address, uint256, bytes memory) {
            bytes memory callData = abi.encodeWithSignature(
                 "withdraw(address,uint256,address)",
                  _asset,
                  _amount,     
                  _to     
            );           
            
            return (address(lendingPool), 0, callData);
     }
    function getUniswapTokenCallData(
        address _assetIn,
        address _assetOut,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _to
    ) internal view  returns (address, uint256, bytes memory){
            address[] memory _path=new address[](2);
            _path[0]=_assetIn;
            _path[1]=_assetOut;
            uint _deadline = block.timestamp + 300;
            bytes memory callData = abi.encodeWithSignature(
                 "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                 _amountIn,
                 _amountOutMin,
                 _path,
                 _to,
                 _deadline
            );                    
            return (address(uniswapRouter), 0, callData);
    }
    function getUniswapExactTokenCallData(
        address _assetIn,
        address _assetOut,
        uint256 _amountOut,
        uint256 _amountInMax,
        address _to
    ) internal view  returns (address, uint256, bytes memory){
            address[] memory _path=new address[](2);
            _path[0]=_assetIn;
            _path[1]=_assetOut;
            uint _deadline = block.timestamp + 300;
            bytes memory callData = abi.encodeWithSignature(
                 "swapTokensForExactTokens(uint256,uint256,address[],address,uint256)",
                 _amountOut,
                 _amountInMax,
                 _path,
                 _to,
                 _deadline
            );                    
            return (address(uniswapRouter), 0, callData);
    }   
    function _updatePosition(
        IJasperVault _jasperVault,
        address _token,
        uint256 _newPositionUnit,
        uint256 _coinType
    ) internal {
        _jasperVault.editCoinType(_token,_coinType);
        _jasperVault.editDefaultPosition(_token, _newPositionUnit);
    }
   
    function _updateExternalPosition(
        IJasperVault _jasperVault,
        address _token,
        address _module,
        int256 _newPositionUnit,
        uint256 _coinType
    ) internal {
        _jasperVault.editExternalCoinType(_token,_module,_coinType);
        _jasperVault.editExternalPosition(
            _token,
            _module,
            _newPositionUnit,
            ""
        );
    
    }

   function removeModule() external override {}
}
