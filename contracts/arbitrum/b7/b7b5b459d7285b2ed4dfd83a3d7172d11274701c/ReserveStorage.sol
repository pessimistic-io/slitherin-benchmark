// (c) 2023 Primex.finance
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ERC165Upgradeable} from "./ERC165Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";

import {IPrimexDNS} from "./IPrimexDNS.sol";
import {IReserveStorage} from "./IReserveStorage.sol";

abstract contract ReserveStorage is
    IReserveStorage,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC165Upgradeable
{
    IPrimexDNS internal dns;
    address internal registry;

    // map pToken address to its transfer restrictions
    mapping(address => TransferRestrictions) public override transferRestrictions;
}

