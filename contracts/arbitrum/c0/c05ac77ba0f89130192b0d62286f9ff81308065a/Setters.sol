// contracts/Setters.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./State.sol";

contract CATERC721Setters is CATERC721State {
    function setTransferCompleted(bytes32 hash) internal {
        _state.completedTransfers[hash] = true;
    }

    function setTokenImplementation(uint16 chainId, bytes32 tokenContract) internal {
        _state.tokenImplementations[chainId] = tokenContract;
    }

    function setWormhole(address wh) internal {
        _state.wormhole = payable(wh);
    }

    function setFinality(uint8 finality) internal {
        _state.provider.finality = finality;
    }

    function setChainId(uint16 chainId) internal {
        _state.provider.chainId = chainId;
    }

    function setEvmChainId(uint256 evmChainId) internal {
        require(evmChainId == block.chainid, "invalid evmChainId");
        _state.evmChainId = evmChainId;
    }

    function setNativeAsset(address nativeAsset) internal {
        _state.nativeAsset = nativeAsset;
    }

    function setMaxSupply(uint256 maxSupply) internal {
        _state.maxSupply = maxSupply;
    }

    function setMintedSupply(uint256 mintedSupply) internal {
        _state.mintedSupply = mintedSupply;
    }

    function setIsInitialized() internal {
        _state.isInitialized = true;
    }

    function setBaseUri(string memory uri) internal {
        _state.baseUri = uri;
    }

    function setSignatureUsed(bytes memory signature) internal {
        _state.signaturesUsed[signature] = true;
    }
}

