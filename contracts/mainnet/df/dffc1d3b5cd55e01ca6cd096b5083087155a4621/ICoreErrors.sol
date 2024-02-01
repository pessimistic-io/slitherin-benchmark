// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

interface IRegistryErrorsV0 {
    error ContractNotFound();
    error ZeroAddressError();
    error FailedToSetCoreRegistry();
    error CoreRegistryInterfaceNotSupported();
    error AddressNotContract();
}

interface ICoreRegistryErrorsV0 {
    error FailedToSetCoreRegistry();
    error FailedToSetConfigContract();
    error FailedTosetDeployerContract();
}

interface IOperatorFiltererConfigErrorsV0 {
    error OperatorFiltererNotFound();
    error InvalidOperatorFiltererDetails();
}

interface ICoreRegistryEnabledErrorsV0 {
    error CoreRegistryNotSet();
}

