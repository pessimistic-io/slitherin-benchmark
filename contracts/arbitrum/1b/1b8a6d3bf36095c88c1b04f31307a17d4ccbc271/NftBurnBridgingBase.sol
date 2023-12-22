// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IWormhole.sol";
import "./BytesLib.sol";

import { FacetInitializable } from "./FacetInitializable.sol";
import { LibNftBurnBridgingBaseStorage } from "./LibNftBurnBridgingBaseStorage.sol";

/**
 * @title  A minimal contract that sets up and implements the Wormhole messaging bridge to 1-way mint an NFT that is assumed to have been burned on the source chain.
 * @notice Modified version of https://github.com/wormhole-foundation/wormhole-scaffolding/blob/main/evm/src/03_nft_burn_bridging/NftBurnBridging.sol
 *  to not need the ERC721 definition and change the size of the tokenIds being passed in
 */
abstract contract NftBurnBridgingBase is FacetInitializable {
    using BytesLib for bytes;

    function __NftBurnBridgingBase_init(IWormhole _wormhole, uint16 _emitterChainId, bytes32 _emitterAddress) internal {
        LibNftBurnBridgingBaseStorage.Layout storage _l = LibNftBurnBridgingBaseStorage.layout();
        _l.wormhole = _wormhole;
        _l.emitterChainId = _emitterChainId;
        _l.emitterAddress = _emitterAddress;
    }

    /**
     * @dev Assuming that the NFT contract will implement this function to avoid a lot of NFT context in what is effectively a wormhole messaging library
     * @param _to The recipient of the NFT that was parsed from the vaa
     * @param _tokenId The token ID of the NFT that was parsed from the vaa
     */
    function _safeMint(address _to, uint256 _tokenId) internal virtual;

    /**
     * @dev The emitter address is the derived public key related to the vaa message. This is to avoid using unexpected vaa messages to mint NFTs
     * @param _wormholeChainId The chain ID of the Wormhole contract that emitted the VAA
     */
    function getEmitterAddress(uint16 _wormholeChainId) external view returns (bytes32) {
        LibNftBurnBridgingBaseStorage.Layout storage _l = LibNftBurnBridgingBaseStorage.layout();
        return (_wormholeChainId == _l.emitterChainId) ? _l.emitterAddress : bytes32(0);
    }

    /**
     * @dev Validates the VAA against our saved emitter address, then assumes the message is comprised of 32 bits for the tokenId and 160 bits for the recipient address
     * @param _vaa The VAA that was emitted by the Wormhole contract. Needs to be parsed to get the message emitter to validate authenticity of the message
     */
    function receiveAndMint(bytes calldata _vaa) external {
        LibNftBurnBridgingBaseStorage.Layout storage _l = LibNftBurnBridgingBaseStorage.layout();
        (IWormhole.VM memory _vm, bool _valid, string memory _reason) = _l.wormhole.parseAndVerifyVM(_vaa);

        if (!_valid) {
            revert LibNftBurnBridgingBaseStorage.FailedVaaParseAndVerification(_reason);
        }

        if (_vm.emitterChainId != _l.emitterChainId) {
            revert LibNftBurnBridgingBaseStorage.WrongEmitterChainId();
        }

        if (_vm.emitterAddress != _l.emitterAddress) {
            revert LibNftBurnBridgingBaseStorage.WrongEmitterAddress();
        }

        if (_l.claimedVaas[_vm.hash]) {
            revert LibNftBurnBridgingBaseStorage.VaaAlreadyClaimed();
        }

        _l.claimedVaas[_vm.hash] = true;

        (uint256 _tokenId, address _evmRecipient) = parsePayload(_vm.payload);
        _safeMint(_evmRecipient, _tokenId);
    }

    /**
     * @dev Validates that the message size is exactly 192 bits (32 bits for the tokenId and 160 bits for the recipient address)
     * @param _message The message that was parsed from the VAA
     * @return tokenId_ The tokenId that was parsed from the message
     * @return evmRecipient_ The recipient address that was parsed from the message
     */
    function parsePayload(bytes memory _message) internal pure returns (uint256 tokenId_, address evmRecipient_) {
        if (_message.length != BytesLib.uint32Size + BytesLib.addressSize) {
            revert LibNftBurnBridgingBaseStorage.InvalidMessageLength();
        }

        tokenId_ = _message.toUint32(0);
        evmRecipient_ = _message.toAddress(BytesLib.uint32Size);
    }
}

