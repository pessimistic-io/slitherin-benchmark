// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

library Network {
    function isCurrentNetwork(bytes4 networkId) internal view returns (bool) {
        uint256 currentchainId;
        assembly {
            currentchainId := chainid()
        }

        bytes1 version = 0x01;
        bytes1 networkType = 0x01;
        bytes1 extraData = 0x00;
        bytes4 currentNetworkId = bytes4(sha256(abi.encode(version, networkType, currentchainId, extraData)));
        return currentNetworkId == networkId;
    }
}

