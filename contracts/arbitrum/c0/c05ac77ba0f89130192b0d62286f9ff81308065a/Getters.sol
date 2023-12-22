// contracts/Getters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./IWormhole.sol";
import "./IERC721Extended.sol";

import "./State.sol";
import "./BytesLib.sol";

contract CATERC721Getters is CATERC721State {
    using BytesLib for bytes;

    function isTransferCompleted(bytes32 hash) public view returns (bool) {
        return _state.completedTransfers[hash];
    }

    function wormhole() public view returns (IWormhole) {
        return IWormhole(_state.wormhole);
    }

    function chainId() public view returns (uint16) {
        return _state.provider.chainId;
    }

    function evmChainId() public view returns (uint256) {
        return _state.evmChainId;
    }

    function tokenContracts(uint16 chainId_) public view returns (bytes32) {
        return _state.tokenImplementations[chainId_];
    }

    function finality() public view returns (uint8) {
        return _state.provider.finality;
    }

    function nativeAsset() public view returns (IERC721Extended) {
        return IERC721Extended(_state.nativeAsset);
    }

    function maxSupply() public view returns (uint256) {
        return _state.maxSupply;
    }

    function mintedSupply() public view returns (uint256) {
        return _state.mintedSupply;
    }

    function isInitialized() public view returns (bool) {
        return _state.isInitialized;
    }

    function baseUri() public view returns (string memory) {
        return _state.baseUri;
    }

    function isSignatureUsed(bytes memory signature) public view returns (bool) {
        return _state.signaturesUsed[signature];
    }

    /*
     * @dev Truncate a 32 byte array to a 20 byte address.
     *      Reverts if the array contains non-0 bytes in the first 12 bytes.
     *
     * @param bytes32 bytes The 32 byte array to be converted.
     */
    function bytesToAddress(bytes32 b) public pure returns (address) {
        require(bytes12(b) == 0, "invalid EVM address");
        return address(uint160(uint256(b)));
    }

    function addressToBytes(address a) public pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    function encodeTransfer(
        CATERC721Structs.CrossChainPayload memory transfer
    ) public pure returns (bytes memory encoded) {
        encoded = abi.encodePacked(
            transfer.tokenAddress,
            transfer.tokenChain,
            transfer.tokenID,
            uint8(bytes(transfer.uri).length),
            transfer.uri,
            transfer.toAddress,
            transfer.toChain
        );
    }

    function decodeTransfer(
        bytes memory encoded
    ) public pure returns (CATERC721Structs.CrossChainPayload memory transfer) {
        uint256 index = 0;

        transfer.tokenAddress = encoded.toBytes32(index);
        index += 32;

        transfer.tokenChain = encoded.toUint16(index);
        index += 2;

        transfer.tokenID = encoded.toUint256(index);
        index += 32;

        // Ignore length due to malformatted payload
        index += 1;
        transfer.uri = string(encoded.slice(index, encoded.length - index - 34));

        // From here we read backwards due malformatted package
        index = encoded.length;

        index -= 2;
        transfer.toChain = encoded.toUint16(index);

        index -= 32;
        transfer.toAddress = encoded.toBytes32(index);
    }
}

