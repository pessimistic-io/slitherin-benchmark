// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IDiamondCut } from "./interfaces_IDiamondCut.sol";

library LibRelayer {
    bytes32 constant RELAYER_STORAGE_POSITION = keccak256("relayer.portal.strateg.io");

    struct RelayerStore {
        address relayer;
    }

    /**
     * @dev return account related storage of the diamond
     */
    function getRelayerStore() internal pure returns (RelayerStore storage store) {
        bytes32 position = RELAYER_STORAGE_POSITION;
        assembly {
            store.slot := position
        }
    }


    function setRelayer(address _relayer) internal {
       getRelayerStore().relayer = _relayer;
    }


    function getRelayer() internal view returns (address) {
       return getRelayerStore().relayer;
    }

    function msgSender() internal view returns (address sender) {
        if (getRelayerStore().relayer == msg.sender && msg.data.length >= 20) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            /// @solidity memory-safe-assembly
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return msg.sender;
        }
    }
}

