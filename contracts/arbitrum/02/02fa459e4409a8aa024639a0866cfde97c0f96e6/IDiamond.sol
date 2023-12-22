// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
// EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535

interface IDiamond {
    enum BeaconCutAction {
        Add,
        Replace,
        Remove
    }
    // Add=0, Replace=1, Remove=2

    struct BeaconCut {
        address beaconAddress;
        BeaconCutAction action;
        bytes4[] functionSelectors;
    }

    event DiamondCut(BeaconCut[] _diamondCut, address _init, bytes _calldata);
}

