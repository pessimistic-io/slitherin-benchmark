// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";

import {Borrower} from "./Borrower.sol";
import {IBorrowerURISource} from "./BorrowerNFT.sol";

contract BorrowerURISource is UUPSUpgradeable, IBorrowerURISource {
    address public owner;

    function initialize(address owner_) external {
        require(owner == address(0));
        owner = owner_;
    }

    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == owner, "Aloe: only owner");
    }

    function uriOf(Borrower) external pure override returns (string memory) {
        return "";
    }
}

