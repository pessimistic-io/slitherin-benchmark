// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "./EnumerableMap.sol";

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @title LOI is Letter of Intent contract
/// @author DeFragDAO
contract LOI {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    EnumerableMap.AddressToUintMap private allocationCommitments;
    address[] public investors;

    function addCommitment(uint256 amount) public {
        if (EnumerableMap.contains(allocationCommitments, msg.sender)) {
            EnumerableMap.remove(allocationCommitments, msg.sender);
            EnumerableMap.set(allocationCommitments, msg.sender, amount);
        } else {
            investors.push(msg.sender);
            EnumerableMap.set(allocationCommitments, msg.sender, amount);
        }
    }

    function getCommitment(address addr) public view returns (uint256) {
        return EnumerableMap.get(allocationCommitments, addr);
    }

    function getCommitmentsTotal() public view returns (uint256) {
        return EnumerableMap.length(allocationCommitments);
    }

    function getInvestors() public view returns (address[] memory) {
        return investors;
    }

    function getInvestorCount() public view returns (uint256) {
        return investors.length;
    }
}

