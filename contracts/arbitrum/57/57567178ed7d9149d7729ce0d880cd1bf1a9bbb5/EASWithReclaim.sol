// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

import {IEAS, AttestationRequest} from "./IEAS.sol";
import {IReclaim} from "./IReclaim.sol";

contract EASWithReclaim {
    IEAS public ieas;
    IReclaim public reclaim;

    constructor(IEAS _ieas, IReclaim _reclaim) {
        ieas = _ieas;
        reclaim = _reclaim;
    }

    function attest(
        AttestationRequest calldata request,
        IReclaim.Proof calldata proof
    ) external returns (bytes32) {
        require(reclaim.verifyProof(proof) == true, "Invalid proof");

        // Attest
        return ieas.attest(request);
    }
}

