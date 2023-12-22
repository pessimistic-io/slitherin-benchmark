// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "./SelfPermit.sol";
import "./PeripheryImmutableState.sol";

import "./V2SwapRouter1EX.sol";
import "./V3SwapRouter1EX.sol";
import "./ApproveAndCall.sol";
import "./MulticallExtended.sol";
import "./ISwapRouter02.sol";

/// @title 1EX Swap Router
contract SwapRouter1EX is
    ISwapRouter02,
    V2SwapRouter1EX,
    V3SwapRouter1EX,
    ApproveAndCall,
    MulticallExtended,
    SelfPermit
{
    constructor(
        address _factoryV2,
        address _factoryV3,
        address _positionManager,
        address _WNative,
        address _oneExFeeCollector,
        uint8 _oneExFeePercent
    )
        ImmutableState(_factoryV2, _positionManager)
        PeripheryImmutableState(_factoryV3, _WNative)
        OneExFee(_oneExFeeCollector, _oneExFeePercent)
    {}
}

