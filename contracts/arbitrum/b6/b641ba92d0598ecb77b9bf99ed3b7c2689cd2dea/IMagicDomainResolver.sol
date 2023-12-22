// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMagicDomainResolver {
    function supportsInterface(bytes4 interfaceID) external view returns (bool);
}
