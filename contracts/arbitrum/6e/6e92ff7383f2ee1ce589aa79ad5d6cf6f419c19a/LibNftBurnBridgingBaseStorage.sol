//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IWormhole.sol";

/**
 * @title LibNftBurnBridgingBaseStorage library
 * @notice This library contains the storage layout and events/errors for the NftBurnBridgingBaseFacet contract.
 */
library LibNftBurnBridgingBaseStorage {
    struct Layout {
        //Core layer Wormhole contract
        IWormhole wormhole;
        //Only VAAs emitted from this Wormhole chain id can mint NFTs
        uint16 emitterChainId;
        //Only VAAs from this emitter can mint NFTs
        bytes32 emitterAddress;
        //VAA hash => claimed flag dictionary to prevent minting from the same VAA twice
        // (e.g. to prevent mint -> burn -> remint)
        mapping(bytes32 => bool) claimedVaas;
    }

    bytes32 internal constant FACET_STORAGE_POSITION = keccak256("spellcaster.storage.bridging.NftBurnBridgingBase");

    function layout() internal pure returns (Layout storage l_) {
        bytes32 _position = FACET_STORAGE_POSITION;
        assembly {
            l_.slot := _position
        }
    }

    error WrongEmitterChainId();
    error WrongEmitterAddress();
    error FailedVaaParseAndVerification(string reason);
    error VaaAlreadyClaimed();
    error InvalidMessageLength();

}

