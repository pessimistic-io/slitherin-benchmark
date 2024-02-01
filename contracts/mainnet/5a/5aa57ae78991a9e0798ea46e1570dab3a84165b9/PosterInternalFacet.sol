// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./console.sol";

import "./LibDiamond.sol";

import "./interfaces_IERC165.sol";
import "./IERC721.sol";

import "./IDiamondLoupe.sol";

import "./UsingDiamondOwner.sol";

import { IERC173 } from "./IERC173.sol";

import { ERC721DInternal } from "./ERC721DInternal.sol";

import {OperatorFilterer} from "./OperatorFilterer.sol";

import {ERC2981} from "./ERC2981.sol";
import {IERC2981} from "./IERC2981.sol";

import {ERC2981Storage} from "./ERC2981Storage.sol";

import "./IERC721Metadata.sol";
import {AccessControlInternal} from "./AccessControlInternal.sol";

import "./UsingDiamondOwner.sol";

import {LibBitmap} from "./LibBitmap.sol";

struct PosterStorage {
    bool isInitialized;
    bool operatorFilteringEnabled;
    uint16 maxBooksPerPoster;
    uint16 activeExhibition;
    uint64 nextTokenId;
    
    address fontDeclarationPointer;
    address wordmarkPointer;
    address defaultQrCodePointer;
    
    address dataContract;
    address gameContract;
    address withdrawAddress;
    
    string nameSingular;
    string defaultExternalLink;
    
    mapping (uint16 => Exhibition) exhibitions;
    mapping (address => LibBitmap.Bitmap) userToMintedInExhibition;
}

struct Exhibition {
    uint16 number;
    address qrCodePointer;
    address representativeBooksPointer;
    string name;
    string externalLink;
}

contract PosterInternalFacet is ERC721DInternal, AccessControlInternal, UsingDiamondOwner {
    bytes32 constant ADMIN = keccak256("admin");
    
    function s() internal pure returns (PosterStorage storage gs) {
        bytes32 position = keccak256("c21.babylon.game.poster.storage.BabylonExhibitionPoster");
        assembly {
            gs.slot := position
        }
    }
    
    function ds() internal pure returns (LibDiamond.DiamondStorage storage) {
        return LibDiamond.diamondStorage();
    }
    
    function get80BitNumberInBytesAtIndex(bytes memory idsBytes, uint idx) internal pure returns (uint80) {
        return uint80(uintByteArrayValueAtIndex(idsBytes, 10, idx));
    }
    
    function uintByteArrayValueAtIndex(bytes memory uintByteArray, uint bytesPerUint, uint index) internal pure returns (uint) {
        uint value;
        
        for (uint i; i < bytesPerUint; ) {
            value <<= 8;
            value |= uint(uint8(uintByteArray[index * bytesPerUint + i]));
            unchecked {++i;}
        }
        
        return value;
    }
    
    function unpackAssets(uint80 assetsPacked)
        internal
        pure
        returns (uint8[10] memory ret)
    {
        for (uint8 i = 0; i < 10; i++) {
            ret[i] = uint8(assetsPacked >> (8 * (9 - i)));
        }
    }
    
    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}

