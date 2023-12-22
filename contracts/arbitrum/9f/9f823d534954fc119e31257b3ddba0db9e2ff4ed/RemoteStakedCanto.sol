//SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {OFT} from "./OFT.sol";

/// @title Remote Staked Canto - Provided by Layer Zero
///
/// @dev This is the Remote Chain LayerZero OFT contract for sCANTO
contract RemoteStakedCanto is OFT {
    constructor(address _lzEndpoint) OFT("Liquid Staked Canto", "sCANTO", _lzEndpoint) {}
}
