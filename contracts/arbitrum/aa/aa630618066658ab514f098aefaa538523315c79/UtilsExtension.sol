/*
    Copyright 2022 Set Labs Inc.

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

import {IJasperVault} from "./IJasperVault.sol";
import {IUtilsModule} from "./IUtilsModule.sol";
import {BaseGlobalExtension} from "./BaseGlobalExtension.sol";
import {IDelegatedManager} from "./IDelegatedManager.sol";
import {IManagerCore} from "./IManagerCore.sol";
import {ISignalSuscriptionModule} from "./ISignalSuscriptionModule.sol";
import { IERC20 } from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract UtilsExtension is BaseGlobalExtension {
    using SafeERC20 for IERC20;
    event WrapExtensionInitialized(
        address indexed _jasperVault,
        address indexed _delegatedManager
    );
    event SetSubscribeStatus(IJasperVault indexed _jasperVault, uint256 status);
    IUtilsModule public immutable utilsModule;
    ISignalSuscriptionModule public immutable signalSuscriptionModule;
    constructor(
        IManagerCore _managerCore,
        IUtilsModule _utilsModule,
        ISignalSuscriptionModule _signalSuscriptionModule
    ) public BaseGlobalExtension(_managerCore) {
        utilsModule = _utilsModule;
        signalSuscriptionModule = _signalSuscriptionModule;
    }


    function resetAndUnSubscribed(IJasperVault _jasperVault) external  onlyUnSubscribed(_jasperVault) onlyOperator(_jasperVault){
            bytes memory callData = abi.encodeWithSelector(
                IUtilsModule.reset.selector,
                _jasperVault
            );
            _invokeManager(_manager(_jasperVault), address(utilsModule), callData);
            //calculate fee
            callData = abi.encodeWithSelector(
                ISignalSuscriptionModule.handleFee.selector,
                _jasperVault
            );
            _invokeManager(_manager(_jasperVault), address(signalSuscriptionModule), callData);

            //update status
            _manager(_jasperVault).setSubscribeStatus(0);
            emit SetSubscribeStatus( _jasperVault,0);
    }



    function reset(IJasperVault _jasperVault) external    
    onlyOperator(_jasperVault) 
    onlyReset(_jasperVault){
          bytes memory callData = abi.encodeWithSelector(
                IUtilsModule.reset.selector,
                _jasperVault
            );
            _invokeManager(_manager(_jasperVault), address(utilsModule), callData);
    }


    function rebalance(IJasperVault _target,IJasperVault _jasperVault,uint256 _ratio) external 
    onlyOperator(_jasperVault) 
    onlyReset(_jasperVault){
            bytes memory callData = abi.encodeWithSelector(
                IUtilsModule.rebalance.selector,
                _target,
                _jasperVault,
                _ratio
            );
            _invokeManager(_manager(_jasperVault), address(utilsModule), callData);                  
            uint256 vaultProfit=_getJasperVaultValue(_jasperVault);
            //calculate  mirror fee
            if(vaultProfit>=_target.maxFollowFee()){
              //traferFrom fee from metamask 
              require(isContract(msg.sender),"caller not contract");
              address metamask=IOwnable(msg.sender).owner();
              address mirrorToken=signalSuscriptionModule.mirrorToken();
              require(mirrorToken!=address(0x00),"invalid mirrorToken");
              uint256 amount=_target.followFee();
              IERC20(mirrorToken).safeTransferFrom(metamask, address(signalSuscriptionModule), amount);
              callData = abi.encodeWithSelector(
                ISignalSuscriptionModule.handleResetFee.selector,
                _target,
                _jasperVault,
                mirrorToken,
                amount
              );
              _invokeManager(_manager(_jasperVault), address(signalSuscriptionModule), callData);
            }
    }


    function isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(_addr) }
        return size > 0;
    }

    //initial
    function initializeModule(
        IDelegatedManager _delegatedManager
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        _initializeModule(_delegatedManager.jasperVault(), _delegatedManager);
    }

    function _initializeModule(
        IJasperVault _jasperVault,
        IDelegatedManager _delegatedManager
    ) internal {
        bytes memory callData = abi.encodeWithSelector(
            IUtilsModule.initialize.selector,
            _jasperVault
        );
        _invokeManager(_delegatedManager, address(utilsModule), callData);
    }

    function initializeExtension(
        IDelegatedManager _delegatedManager
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);

        emit WrapExtensionInitialized(
            address(jasperVault),
            address(_delegatedManager)
        );
    }
    function initializeModuleAndExtension(
        IDelegatedManager _delegatedManager
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);
        _initializeModule(jasperVault, _delegatedManager);

        emit WrapExtensionInitialized(
            address(jasperVault),
            address(_delegatedManager)
        );
    }

    function removeExtension() external override {
        IDelegatedManager delegatedManager = IDelegatedManager(msg.sender);
        IJasperVault jasperVault = delegatedManager.jasperVault();
        _removeExtension(jasperVault, delegatedManager);
    }

  


}

