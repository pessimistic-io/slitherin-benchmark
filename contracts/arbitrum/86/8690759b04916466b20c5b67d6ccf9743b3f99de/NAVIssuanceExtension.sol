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

import {Address} from "./Address.sol";
import {SafeMath} from "./SafeMath.sol";

import { IJasperVault } from "./IJasperVault.sol";
import {INAVIssuanceModule} from "./INAVIssuanceModule.sol";
import {INAVIssuanceHook} from "./INAVIssuanceHook.sol";

import {PreciseUnitMath} from "./PreciseUnitMath.sol";

import {BaseGlobalExtension} from "./BaseGlobalExtension.sol";
import {IDelegatedManager} from "./IDelegatedManager.sol";
import {IManagerCore} from "./IManagerCore.sol";


/**
 * @title IssuanceExtension
 * @author Set Protocol
 *
 * Smart contract global extension which provides DelegatedManager owner and methodologist the ability to accrue and split
 * issuance and redemption fees. Owner may configure the fee split percentages.
 *
 * Notes
 * - the fee split is set on the Delegated Manager contract
 * - when fees distributed via this contract will be inclusive of all fee types that have already been accrued
 */
contract NAVIssuanceExtension is BaseGlobalExtension {
    using Address for address;
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;

    /* ============ Events ============ */

    event IssuanceExtensionInitialized(
        address indexed _jasperVault,
        address indexed _delegatedManager
    );

    event FeesDistributed(
        address _jasperVault,
        address indexed _ownerFeeRecipient,
        address indexed _methodologist,
        uint256 _ownerTake,
        uint256 _methodologistTake
    );

    /* ============ State Variables ============ */
    struct NAVIssuanceSettings {
        INAVIssuanceHook managerIssuanceHook; // Issuance hook configurations
        INAVIssuanceHook managerRedemptionHook; // Redemption hook configurations
        address[] reserveAssets; // Allowed reserve assets - Must have a price enabled with the price oracle
        address feeRecipient; // Manager fee recipient
        uint256[2] managerFees; // Manager fees. 0 index is issue and 1 index is redeem fee (0.01% = 1e14, 1% = 1e16)
        uint256 maxManagerFee; // Maximum fee manager is allowed to set for issue and redeem
        uint256 premiumPercentage; // Premium percentage (0.01% = 1e14, 1% = 1e16). This premium is a buffer around oracle
        // prices paid by user to the JasperVault, which prevents arbitrage and oracle front running
        uint256 maxPremiumPercentage; // Maximum premium percentage manager is allowed to set (configured by manager)
        uint256 minSetTokenSupply; // Minimum JasperVault supply required for issuance and redemption
        // to prevent dramatic inflationary changes to the JasperVault's position multiplier
    }
    // Instance of navIssuanceModule
    INAVIssuanceModule public immutable navIssuanceModule;

    /* ============ Constructor ============ */

    constructor(
        IManagerCore _managerCore,
        INAVIssuanceModule _navIssuanceModule
    ) public BaseGlobalExtension(_managerCore) {
        navIssuanceModule = _navIssuanceModule;
    }

    /* ============ External Functions ============ */

    /**
     * ANYONE CALLABLE: Distributes fees accrued to the DelegatedManager. Calculates fees for
     * owner and methodologist, and sends to owner fee recipient and methodologist respectively.
     */
    function distributeFees(IJasperVault _jasperVault) public {
        IDelegatedManager delegatedManager = _manager(_jasperVault);

        uint256 totalFees = _jasperVault.balanceOf(address(delegatedManager));

        address methodologist = delegatedManager.methodologist();
        address ownerFeeRecipient = delegatedManager.ownerFeeRecipient();

        uint256 ownerTake = totalFees.preciseMul(
            delegatedManager.ownerFeeSplit()
        );
        uint256 methodologistTake = totalFees.sub(ownerTake);

        if (ownerTake > 0) {
            delegatedManager.transferTokens(
                address(_jasperVault),
                ownerFeeRecipient,
                ownerTake
            );
        }

        if (methodologistTake > 0) {
            delegatedManager.transferTokens(
                address(_jasperVault),
                methodologist,
                methodologistTake
            );
        }

        emit FeesDistributed(
            address(_jasperVault),
            ownerFeeRecipient,
            methodologist,
            ownerTake,
            methodologistTake
        );
    }

    function initializeModule(
        IDelegatedManager _delegatedManager,
        NAVIssuanceSettings memory _navIssuanceSettings,
        address[] memory _iROwer
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        require(
            _delegatedManager.isInitializedExtension(address(this)),
            "Extension must be initialized"
        );

        _initializeModule(
            _delegatedManager.jasperVault(),
            _delegatedManager,
            _navIssuanceSettings,
            _iROwer
        );
    }

    /**
     * ONLY OWNER: Initializes IssuanceExtension to the DelegatedManager.
     *
     * @param _delegatedManager     Instance of the DelegatedManager to initialize
     */
    function initializeExtension(IDelegatedManager _delegatedManager)
        external
        onlyOwnerAndValidManager(_delegatedManager)
    {
        require(
            _delegatedManager.isPendingExtension(address(this)),
            "Extension must be pending"
        );

        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);

        emit IssuanceExtensionInitialized(
            address(jasperVault),
            address(_delegatedManager)
        );
    }

    function initializeModuleAndExtension(
        IDelegatedManager _delegatedManager,
        NAVIssuanceSettings memory _navIssuanceSettings,
        address[] memory _iROwer
    ) external onlyOwnerAndValidManager(_delegatedManager) {
        require(
            _delegatedManager.isPendingExtension(address(this)),
            "Extension must be pending"
        );

        IJasperVault jasperVault = _delegatedManager.jasperVault();

        _initializeExtension(jasperVault, _delegatedManager);
        _initializeModule(jasperVault, _delegatedManager, _navIssuanceSettings,_iROwer);

        emit IssuanceExtensionInitialized(
            address(jasperVault),
            address(_delegatedManager)
        );
    }

    /**
     * ONLY MANAGER: Remove an existing JasperVault and DelegatedManager tracked by the IssuanceExtension
     */
    function removeExtension() external override {
        IDelegatedManager delegatedManager = IDelegatedManager(msg.sender);
        IJasperVault jasperVault = delegatedManager.jasperVault();

        _removeExtension(jasperVault, delegatedManager);
    }

    function addReserveAsset(IJasperVault _jasperVault, uint256 _reserveAsset)
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            INAVIssuanceModule.addReserveAsset.selector,
            _jasperVault,
            _reserveAsset
        );
        _invokeManager(
            _manager(_jasperVault),
            address(navIssuanceModule),
            callData
        );
    }

    function removeReserveAsset(IJasperVault _jasperVault, uint256 _reserveAsset)
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            INAVIssuanceModule.removeReserveAsset.selector,
            _jasperVault,
            _reserveAsset
        );
        _invokeManager(
            _manager(_jasperVault),
            address(navIssuanceModule),
            callData
        );
    }

    function editPremium(IJasperVault _jasperVault, uint256 _premiumPercentage)
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            INAVIssuanceModule.editPremium.selector,
            _jasperVault,
            _premiumPercentage
        );
        _invokeManager(
            _manager(_jasperVault),
            address(navIssuanceModule),
            callData
        );
    }

    function editManagerFee(
        IJasperVault _jasperVault,
        uint256 _managerFeePercentage,
        uint256 _managerFeeIndex
    ) external onlyOwner(_jasperVault) {
        bytes memory callData = abi.encodeWithSelector(
            INAVIssuanceModule.editManagerFee.selector,
            _jasperVault,
            _managerFeePercentage,
            _managerFeeIndex
        );
        _invokeManager(
            _manager(_jasperVault),
            address(navIssuanceModule),
            callData
        );
    }

    /**
     * ONLY OWNER: Updates fee recipient on navIssuanceModule
     *
     * @param _jasperVault         Instance of the JasperVault to update fee recipient for
     * @param _newFeeRecipient  Address of new fee recipient. This should be the address of the DelegatedManager
     */
    function editFeeRecipient(IJasperVault _jasperVault, address _newFeeRecipient)
        external
        onlyOwner(_jasperVault)
    {
        bytes memory callData = abi.encodeWithSelector(
            INAVIssuanceModule.editFeeRecipient.selector,
            _jasperVault,
            _newFeeRecipient
        );
        _invokeManager(
            _manager(_jasperVault),
            address(navIssuanceModule),
            callData
        );
    }

    /* ============ Internal Functions ============ */

    function _initializeModule(
        IJasperVault _jasperVault,
        IDelegatedManager _delegatedManager,
        NAVIssuanceSettings memory _navIssuanceSettings,
        address[] memory _iROwer
    ) internal {
        bytes memory callData = abi.encodeWithSelector(
            INAVIssuanceModule.initialize.selector,
            _jasperVault,
            _navIssuanceSettings,
            _iROwer
        );
        _invokeManager(_delegatedManager, address(navIssuanceModule), callData);
    }
}

