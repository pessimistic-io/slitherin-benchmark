// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IRAYC {
    function walletOfOwner(address _owner)
        external
        view
        returns (uint256[] memory);
}

