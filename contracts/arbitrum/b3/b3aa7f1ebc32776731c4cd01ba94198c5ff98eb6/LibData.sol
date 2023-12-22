// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Structs.sol";

library LibData {
    bytes32 internal constant DATA_STORAGE_POSITION = keccak256("diamond.standard.data.storage");

    struct DiamondData {
        mapping(bytes32 => BridgeInfo) transferInfo;
        mapping(bytes32 => bool) transfers;
    }

    function dataStorage() internal pure returns (DiamondData storage ds) {
        bytes32 position = DATA_STORAGE_POSITION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            ds.slot := position
        }
    }

    event Bridge(address user, uint64 chainId, address dstToken, uint256 amount, uint64 nonce, bytes32 transferId, string bridge);

    event Swap(address user, address srcToken, address toToken, uint256 amount, uint256 returnAmount);

    event Relayswap(address receiver, address toToken, uint256 returnAmount);
}

