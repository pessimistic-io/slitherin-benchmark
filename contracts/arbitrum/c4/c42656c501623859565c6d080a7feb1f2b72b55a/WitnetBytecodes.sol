// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "./IWitnetBytecodes.sol";
import "./IWitnetBytecodesErrors.sol";
import "./IWitnetBytecodesEvents.sol";

abstract contract WitnetBytecodes
    is
        IWitnetBytecodes,
        IWitnetBytecodesErrors,
        IWitnetBytecodesEvents
{}
