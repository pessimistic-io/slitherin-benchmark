// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { BaseTransfersNative } from "./BaseTransfersNative.sol";
import { BaseSimpleSwap, CoreSimpleSwapConfig } from "./BaseSimpleSwap.sol";
import { BaseAccessControl, CoreAccessControlConfig } from "./BaseAccessControl.sol";
import { BaseFees, CoreFeesConfig } from "./BaseFees.sol";
import { CoreMulticall } from "./CoreMulticall.sol";
import {     WETH9NativeWrapper,     BaseNativeWrapperConfig } from "./WETH9NativeWrapper.sol";
import { BaseNativeWrapperConfig } from "./BaseNativeWrapper.sol";
import { BasePermissionedExecution } from "./BasePermissionedExecution.sol";

contract TradingVault is
    WETH9NativeWrapper,
    BaseTransfersNative,
    BaseSimpleSwap,
    BasePermissionedExecution,
    CoreMulticall
{
    constructor(
        BaseNativeWrapperConfig memory baseNativeWrapperConfig,
        CoreAccessControlConfig memory coreAccessControlConfig,
        CoreSimpleSwapConfig memory coreSimpleSwapConfig,
        CoreFeesConfig memory coreFeesConfig
    )
        WETH9NativeWrapper(baseNativeWrapperConfig)
        BaseAccessControl(coreAccessControlConfig)
        BaseSimpleSwap(coreSimpleSwapConfig)
        BaseFees(coreFeesConfig)
    {}
}

