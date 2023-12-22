// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {Ownable} from "./Ownable.sol";

contract RevealModule is Ownable {
    string public GANGZ_PROVENANCE = "";
    uint256 public REVEAL_TIMESTAMP;

    constructor() {}

    function setProvenanceHash(string memory provenanceHash) public onlyOwner {
        GANGZ_PROVENANCE = provenanceHash;
    }

    function setRevealTimestamp(uint256 _newRevealTimestamp) public onlyOwner {
        REVEAL_TIMESTAMP = _newRevealTimestamp;
    }
}

