// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { LibDiamond } from "./LibDiamond.sol";
import { Ownable } from "./Ownable.sol";
import { AppStorage } from "./LibAppStorage.sol";

contract OwnershipFacet is Ownable {
    AppStorage internal s;

    function transferOwnership(address _newOwner) external onlyOwner {
        s.ownerCandidate = _newOwner;
    }

    function claimOwnership() external {
        require(s.ownerCandidate == msg.sender, "Ownership: Not candidate");
        LibDiamond.setContractOwner(msg.sender);
        delete s.ownerCandidate;
    }

    function owner() external view returns (address owner_) {
        owner_ = LibDiamond.contractOwner();
    }

    function ownerCandidate() external view returns (address ownerCandidate_) {
        ownerCandidate_ = s.ownerCandidate;
    }
}

