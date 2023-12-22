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
import {ISignalSuscriptionModule} from "./ISignalSuscriptionModule.sol";
import {IStakingModule} from "./IStakingModule.sol";
import {IJasperVault} from "./IJasperVault.sol";

import {BaseGlobalExtension} from "./BaseGlobalExtension.sol";
import {IDelegatedManager} from "./IDelegatedManager.sol";
import {IManagerCore} from "./IManagerCore.sol";

contract StakingExtension is BaseGlobalExtension {
    event InvokeFail(
        address indexed _manage,
        address _wrapModule,
        string _reason,
        bytes _callData
    );
    event StakingExtensionInitialized(
        address indexed _jasperVault,
        address indexed _delegatedManager
    );

    IStakingModule public immutable stakingModule;
    ISignalSuscriptionModule public immutable signalSuscriptionModule;

    constructor(
        IManagerCore _managerCore,
        IStakingModule _stakingModule,
        ISignalSuscriptionModule _signalSuscriptionModule
    ) public BaseGlobalExtension(_managerCore) {
        stakingModule = _stakingModule;
        signalSuscriptionModule = _signalSuscriptionModule;
    }

    function stake(
        IJasperVault _jasperVault,
        address _stakeContract,
        address _component,
        string memory _adapterName,
        uint256 _componentPositionUnits
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        ValidAdapter(_jasperVault, address(stakingModule), _adapterName)
    {
        bytes memory callData = abi.encodeWithSelector(
            IStakingModule.stake.selector,
            _jasperVault,
            _stakeContract,
            _component,
            _adapterName,
            _componentPositionUnits
        );
        _invokeManager(
            _manager(_jasperVault),
            address(stakingModule),
            callData
        );
    }

    function unstake(
        IJasperVault _jasperVault,
        address _stakeContract,
        address _component,
        string memory _adapterName,
        uint256 _componentPositionUnits
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        ValidAdapter(_jasperVault, address(stakingModule), _adapterName)
    {
        bytes memory callData = abi.encodeWithSelector(
            IStakingModule.unstake.selector,
            _jasperVault,
            _stakeContract,
            _component,
            _adapterName,
            _componentPositionUnits
        );
        _invokeManager(
            _manager(_jasperVault),
            address(stakingModule),
            callData
        );
    }

    function stakeWithFollowers(
        IJasperVault _jasperVault,
        address _stakeContract,
        address _component,
        string memory _adapterName,
        uint256 _componentPositionUnits
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        ValidAdapter(_jasperVault, address(stakingModule), _adapterName)
    {

       bytes memory callData = abi.encodeWithSelector(
            IStakingModule.stake.selector,
            _jasperVault,
            _stakeContract,
            _component,
            _adapterName,
            _componentPositionUnits
        );
        _invokeManager(
            _manager(_jasperVault),
            address(stakingModule),
            callData
        );
        address[] memory followers = signalSuscriptionModule.get_followers(
            address(_jasperVault)
        );
        for (uint256 i = 0; i < followers.length; i++) {
            bytes memory callData = abi.encodeWithSelector(
                IStakingModule.stake.selector,
                IJasperVault(followers[i]),
                _stakeContract,
                _component,
                _adapterName,
                _componentPositionUnits
            );
            _execute(
                _manager(IJasperVault(followers[i])),
                address(stakingModule),
                callData
            );
        }

         callData = abi.encodeWithSelector(
            ISignalSuscriptionModule.exectueFollowStart.selector,
            address(_jasperVault)
        );
        _invokeManager(_manager(_jasperVault), address(signalSuscriptionModule), callData);
    }

    function unstakeWithFollowers(
        IJasperVault _jasperVault,
        address _stakeContract,
        address _component,
        string memory _adapterName,
        uint256 _componentPositionUnits
    )
        external
        onlyReset(_jasperVault)
        onlyOperator(_jasperVault)
        ValidAdapter(_jasperVault, address(stakingModule), _adapterName)
    {
        bytes memory callData = abi.encodeWithSelector(
            IStakingModule.unstake.selector,
            _jasperVault,
            _stakeContract,
            _component,
            _adapterName,
            _componentPositionUnits
        );
        _invokeManager(
            _manager(_jasperVault),
            address(stakingModule),
            callData
        );
        address[] memory followers = signalSuscriptionModule.get_followers(
            address(_jasperVault)
        );
        for (uint256 i = 0; i < followers.length; i++) {
            bytes memory callData = abi.encodeWithSelector(
                IStakingModule.unstake.selector,
                IJasperVault(followers[i]),
                _stakeContract,
                _component,
                _adapterName,
                _componentPositionUnits
            );
            _execute(
                _manager(IJasperVault(followers[i])),
                address(stakingModule),
                callData
            );
        }
        callData = abi.encodeWithSelector(
            ISignalSuscriptionModule.exectueFollowStart.selector,
            address(_jasperVault)
        );
        _invokeManager(_manager(_jasperVault), address(signalSuscriptionModule), callData);
    }

    function _execute(
        IDelegatedManager manager,
        address module,
        bytes memory callData
    ) internal {
        try manager.interactManager(module, callData) {} catch Error(
            string memory reason
        ) {
            emit InvokeFail(address(manager), module, reason, callData);
        }
    }

    //--------------------------
    function initializeModule(
        IDelegatedManager _delegatedManager
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        _initializeModule(_delegatedManager.jasperVault(), _delegatedManager);
    }

    //----------------------------
    function initializeExtension(
        IDelegatedManager _delegatedManager
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);

        emit StakingExtensionInitialized(
            address(jasperVault),
            address(_delegatedManager)
        );
    }

    //------------------
    function initializeModuleAndExtension(
        IDelegatedManager _delegatedManager
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);

        _initializeModule(jasperVault, _delegatedManager);

        emit StakingExtensionInitialized(
            address(jasperVault),
            address(_delegatedManager)
        );
    }

    //--------------------
    function removeExtension() external override {
        IDelegatedManager delegatedManager = IDelegatedManager(msg.sender);
        IJasperVault jasperVault = delegatedManager.jasperVault();

        _removeExtension(jasperVault, delegatedManager);
    }

    function _initializeModule(
        IJasperVault _jasperVault,
        IDelegatedManager _delegatedManager
    ) internal {
        bytes memory callData = abi.encodeWithSelector(
            stakingModule.initialize.selector,
            _jasperVault
        );
        _invokeManager(_delegatedManager, address(stakingModule), callData);
    }
}

