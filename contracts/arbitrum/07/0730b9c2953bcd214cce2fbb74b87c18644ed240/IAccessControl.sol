// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IAccessControlFacet {
    function getOffchainActionsUrl()
        external
        view
        returns (string memory offchainActionsUrl);
}

