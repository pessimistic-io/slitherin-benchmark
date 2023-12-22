// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./Ownable.sol";

import "./IZKBridgeSBT.sol";

contract OSBT is Ownable, IZKBridgeSBT, ERC721 {
    address public bridge;

    string private metadataUri;

    modifier onlyBridge() {
        require(msg.sender == bridge, "caller is not the bridge");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _bridge
    ) ERC721(_name, _symbol) {
        bridge = _bridge;
    }

    function zkBridgeMint(
        address _to,
        uint256 _tokenId,
        string memory tokenURI_
    ) external override onlyBridge {
        _mint(_to, _tokenId);
    }


    function tokenURI(
        uint256 _tokenId
    ) public view override returns (string memory) {
        require(_exists(_tokenId), "URI query for nonexistent token");
        return metadataUri;
    }

    function setMetadataUri(string memory _newMetadataUri) external onlyOwner {
        metadataUri = _newMetadataUri;
    }
}

