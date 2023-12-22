// SPDX-License-Identifier: MIT

// Deployed with the Atlas IDE
// https://app.atlaszk.com

pragma solidity ^0.8.7;
import "./Ownable.sol";
import "./ERC721.sol";
import "./ILayerZeroEndpoint.sol";
import "./ILayerZeroReceiver.sol";

contract HoleTo is Ownable, ERC721, ILayerZeroReceiver {
    uint256 counter = 0;
    uint256 nextId = 0;
    uint256 private MAX = 10000000;
    ILayerZeroEndpoint public endpoint = ILayerZeroEndpoint(0x3c2269811836af69497E5F486A85D7316753cf62);

    event ReceiveNFT(
        uint16 _srcChainId,
        address _from,
        uint256 _tokenId,
        uint256 counter
    );

   constructor() ERC721("HOLE NFT", "HOLE") {

    }

    function lzReceive(
        uint16 _srcChainId,
        bytes memory _from,
        uint64,
        bytes memory _payload
    ) external override {
        require(msg.sender == address(endpoint));
        address from;
        assembly {
            from := mload(add(_from, 20))
        }
        (address toAddress, uint256 tokenId) = abi.decode(
            _payload,
            (address, uint256)
        );
        // mint the tokens
        _safeMint(toAddress, tokenId);
        counter += 1;
        emit ReceiveNFT(_srcChainId, toAddress, tokenId, counter);
    }
}

