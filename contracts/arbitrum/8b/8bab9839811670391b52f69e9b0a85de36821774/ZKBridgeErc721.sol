// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ECDSA.sol";

import "./IZKBridgeErc721.sol";

contract ZKBridgeErc721 is IZKBridgeErc721, ERC721Upgradeable, OwnableUpgradeable {
    using ECDSA for bytes32;

    //===================================================
    //==================     event     ==================
    //===================================================
    event SetBaseURI(string oldURI, string newURI);
    event SetSigner(address oldSigner, address newSigner);
    event SetAttribute(uint256 tokenId, string[] key, string[] value);

    //===================================================
    //==================    variable   ==================
    //===================================================
    address public bridge;
    address public signer;
    string public metadataURI;
    mapping(uint256 => string) private tokenURIs;
    mapping(uint256 => mapping(string => string)) public attribute;

    modifier onlyBridge() {
        require(msg.sender == bridge, "caller is not the bridge");
        _;
    }

    //===================================================
    //============== transaction function ===============
    //===================================================
    function initialize(
        string memory _name,
        string memory _symbol,
        string memory _metadataURI,
        address _bridge
    ) public initializer {
        __ERC721_init(_name, _symbol);
        __Ownable_init();
        metadataURI = _metadataURI;
        bridge = _bridge;
    }

    function zkBridgeMint(address _to, uint256 _tokenId, string memory tokenURI_) external override onlyBridge {
        _mint(_to, _tokenId);
    }

    function zkBridgeBurn(uint256 _tokenId) external override onlyBridge {
        require(_exists(_tokenId), "Burn of nonexistent token");
        _burn(_tokenId);
    }

    function setAttribute(
        uint256 _tokenId,
        string[] memory _key,
        string[] memory _value,
        bytes memory _signature
    ) external {
        bytes32 messageHash = keccak256(abi.encode(_tokenId, _key, _value));
        require(signer == messageHash.toEthSignedMessageHash().recover(_signature), "invalid signature");
        require(_key.length == _value.length, "invalid params");
        for (uint256 i; i < _key.length; i++) {
            attribute[_tokenId][_key[i]] = _value[i];
        }
        emit SetAttribute(_tokenId, _key, _value);
    }

    //===================================================
    //=============== view/pure function ================
    //===================================================
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return metadataURI;
    }

    //===================================================
    //=============== governance function ===============
    //===================================================
    function setBaseURI(string memory _newMetadataURI) external onlyOwner {
        emit SetBaseURI(metadataURI, _newMetadataURI);
        metadataURI = _newMetadataURI;
    }

    function setSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "not zero");
        emit SetSigner(signer, _signer);
        signer = _signer;
    }
}

