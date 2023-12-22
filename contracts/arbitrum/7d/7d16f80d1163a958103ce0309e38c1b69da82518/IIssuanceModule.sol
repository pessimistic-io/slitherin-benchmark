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

import { IJasperVault } from "./IJasperVault.sol";

/**
 * @title IIssuanceModule
 * @author Set Protocol
 *
 * Interface for interacting with Issuance module interface.
 */
interface IIssuanceModule {
    function updateIssueFee(IJasperVault _jasperVault, uint256 _newIssueFee) external;
    function updateRedeemFee(IJasperVault _jasperVault, uint256 _newRedeemFee) external;
    function updateFeeRecipient(IJasperVault _jasperVault, address _newRedeemFee) external;

    function initialize(
        IJasperVault _jasperVault,
        uint256 _maxManagerFee,
        uint256 _managerIssueFee,
        uint256 _managerRedeemFee,
        address _feeRecipient,
        address _managerIssuanceHook,
        address _iROwers
    ) external;
}

