// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./Oneminutes.sol";

contract NFTAirdropper is Ownable {

    // Add Oneminutes contract instance
    Oneminutes public oneminutes;

    // Constructor
    constructor(Oneminutes _oneminutes) {
        oneminutes = _oneminutes;
    }

    // Airdrop function
    function airdrop(uint256[] memory _airdropTokenIds, address[] memory _recipients) public onlyOwner {
        require(_airdropTokenIds.length == _recipients.length, "Token IDs and recipients length mismatch");
        for (uint256 i = 0; i < _recipients.length; i++) {
            oneminutes.mintTo(_recipients[i], _airdropTokenIds[i]);
        }
    }
}

