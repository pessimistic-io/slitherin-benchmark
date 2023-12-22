// SPDX-License-Identifier: UNLICENSED
//
//  ██▓███  ▒█████  ▄▄▄█████▓ ██▓ ▒█████   ███▄    █     ▄▄▄       ██▀███   ▄▄▄▄    ██▓▄▄▄█████▓▓█████  ██▀███
// ▓██░  ██▒██▒  ██▒▓  ██▒ ▓▒▓██▒▒██▒  ██▒ ██ ▀█   █    ▒████▄    ▓██ ▒ ██▒▓█████▄ ▓██▒▓  ██▒ ▓▒▓█   ▀ ▓██ ▒ ██▒
// ▓██░ ██▓▒██░  ██▒▒ ▓██░ ▒░▒██▒▒██░  ██▒▓██  ▀█ ██▒   ▒██  ▀█▄  ▓██ ░▄█ ▒▒██▒ ▄██▒██▒▒ ▓██░ ▒░▒███   ▓██ ░▄█ ▒
// ▒██▄█▓▒ ▒██   ██░░ ▓██▓ ░ ░██░▒██   ██░▓██▒  ▐▌██▒   ░██▄▄▄▄██ ▒██▀▀█▄  ▒██░█▀  ░██░░ ▓██▓ ░ ▒▓█  ▄ ▒██▀▀█▄
// ▒██▒ ░  ░ ████▓▒░  ▒██▒ ░ ░██░░ ████▓▒░▒██░   ▓██░    ▓█   ▓██▒░██▓ ▒██▒░▓█  ▀█▓░██░  ▒██▒ ░ ░▒████▒░██▓ ▒██▒
// ▒▓▒░ ░  ░ ▒░▒░▒░   ▒ ░░   ░▓  ░ ▒░▒░▒░ ░ ▒░   ▒ ▒     ▒▒   ▓▒█░░ ▒▓ ░▒▓░░▒▓███▀▒░▓    ▒ ░░   ░░ ▒░ ░░ ▒▓ ░▒▓░
// ░▒ ░      ░ ▒ ▒░     ░     ▒ ░  ░ ▒ ▒░ ░ ░░   ░ ▒░     ▒   ▒▒ ░  ░▒ ░ ▒░▒░▒   ░  ▒ ░    ░     ░ ░  ░  ░▒ ░ ▒░
// ░░      ░ ░ ░ ▒    ░       ▒ ░░ ░ ░ ▒     ░   ░ ░      ░   ▒     ░░   ░  ░    ░  ▒ ░  ░         ░     ░░   ░
//             ░ ░            ░      ░ ░           ░          ░  ░   ░      ░       ░              ░  ░   ░
//
// "Approach, aspiring alchemists; render tribute at Etheria's gate.
//  Prove your worth to the Admission Arbiter, and enter the alchemic state." - Aetherion, Etheria's Gatekeeper

pragma solidity >=0.8.0;

import {Address} from "./Address.sol";
import {Operatable} from "./Operatable.sol";

contract PotionArbiter is Operatable {
    using Address for address;

    struct Call {
        address callees;
        bytes data;
    }

    constructor(address _owner) Operatable(_owner) {}

    function execute(Call[] calldata calls) external onlyOperators {
        for (uint256 i = 0; i < calls.length; ) {
            address callee = calls[i].callees;
            bytes memory data = calls[i].data;

            callee.functionCall(data);

            unchecked {
                ++i;
            }
        }
    }
}

