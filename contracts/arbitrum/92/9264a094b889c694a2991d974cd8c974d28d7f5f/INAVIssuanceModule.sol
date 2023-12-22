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
pragma solidity 0.6.10;
pragma experimental "ABIEncoderV2";

import {IJasperVault} from "./IJasperVault.sol";
import {INAVIssuanceHook} from "./INAVIssuanceHook.sol";

interface INAVIssuanceModule {
    struct NAVIssuanceSettings {
        INAVIssuanceHook managerIssuanceHook; // Issuance hook configurations
        INAVIssuanceHook managerRedemptionHook; // Redemption hook configurations
        address[] reserveAssets; // Allowed reserve assets - Must have a price enabled with the price oracle
        address feeRecipient; // Manager fee recipient
        uint256[2] managerFees; // Manager fees. 0 index is issue and 1 index is redeem fee (0.01% = 1e14, 1% = 1e16)
        uint256 maxManagerFee; // Maximum fee manager is allowed to set for issue and redeem
        uint256 premiumPercentage; // Premium percentage (0.01% = 1e14, 1% = 1e16). This premium is a buffer around oracle
        // prices paid by user to the SetToken, which prevents arbitrage and oracle front running
        uint256 maxPremiumPercentage; // Maximum premium percentage manager is allowed to set (configured by manager)
        uint256 minSetTokenSupply; // Minimum SetToken supply required for issuance and redemption
        // to prevent dramatic inflationary changes to the SetToken's position multiplier
    }

    function initialize(
        IJasperVault _jasperVault,
        NAVIssuanceSettings memory _navIssuanceSettings,
        address[] memory _iROwer
    ) external;

    function issue(
        IJasperVault _jasperVault,
        address _reserveAsset,
        uint256 _reserveAssetQuantity,
        uint256 _minSetTokenReceiveQuantity,
        address _to
    ) external;

    function redeem(
        IJasperVault _jasperVault,
        address _reserveAsset,
        uint256 _setTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address _to
    ) external;

    function addReserveAsset(IJasperVault _jasperVault, address _reserveAsset)
        external;

    function removeReserveAsset(IJasperVault _jasperVault, address _reserveAsset)
        external;

    function editPremium(IJasperVault _jasperVault, uint256 _premiumPercentage)
        external;

    function editManagerFee(
        IJasperVault _jasperVault,
        uint256 _managerFeePercentage,
        uint256 _managerFeeIndex
    ) external;

    function editFeeRecipient(IJasperVault _jasperVault, address _managerFeeRecipient)
        external;
}

