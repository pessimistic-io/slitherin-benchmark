// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

interface INftStore {
    function addPackWhitelist(uint256 _packId, address _user)  external;
}
