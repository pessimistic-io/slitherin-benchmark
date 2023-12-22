// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity ^0.8.19;

import "./OwnableUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";

import "./console.sol";


contract Spirit is ERC721EnumerableUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using MathUpgradeable for uint256;

    uint256 public maxSupply;
    uint256 public mintPriceVKA;
    address public VKA;
    address public Treasury;

    string public baseURI;
    uint256 public tokenIds;
    bytes32 public merkleRoot;

    mapping(uint256 => string) private _tokenURIs;

    event MerkleRootUpdated(bytes32 _merkleRoot);
    event BaseURIUpdated(string _URI);
    event TokenURIChanged(uint256 tokenId, string _tokenURI);
    event MintPriceUpdated(uint256 _price);
    event TreasuryUpdated(address _Treasury);
    event SpiritMinted(address _claimer, uint256 _id);
    event MaxSupplyChanged(uint256 _maxSupply);
    event WhitelistStartDateChanged(uint256 _date);
    event PublicStartDateChanged(uint256 _date);

    mapping(address => bool) public hasMinted;
    uint256 public whitelistStartDate;
    uint256 public publicStartDate;

    function initialize(address _VKA) external initializer {
        require(_VKA != address(0), "VKA address cannot be 0");
        VKA = _VKA;
        maxSupply = 500;

        __ERC721_init("SPIRIT", "SPIRIT");
        __ERC721Enumerable_init();
        __Ownable_init();
    }

    // -- Owner functions -- //

    function setWhitelistStartDate(uint256 _date) external onlyOwner {
        whitelistStartDate = _date;
        emit WhitelistStartDateChanged(_date);
    }

    function setPublicStartDate(uint256 _date) external onlyOwner {
        publicStartDate = _date;
        emit PublicStartDateChanged(_date);
    }

    function setTreasury(address _Treasury) external onlyOwner {
        require(_Treasury != address(0), "Treasury address cannot be 0");
        Treasury = _Treasury;
        emit TreasuryUpdated(_Treasury);
    }

    function setMaxSupply(uint256 _maxSupply) external onlyOwner {
        require(_maxSupply > 0, "Max supply must be greater than 0");
        maxSupply = _maxSupply;
        emit MaxSupplyChanged(_maxSupply);
    }

    function setRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(_merkleRoot);
    }

    function setBaseURI(string memory _URI) public onlyOwner {
        baseURI = _URI;
        emit BaseURIUpdated(_URI);
    }

    function overrideTokenURI(uint256 tokenId, string memory _tokenURI) public onlyOwner {
        _setTokenURI(tokenId, _tokenURI);
        emit TokenURIChanged(tokenId, _tokenURI);
    }

    function setMintPriceVKA(uint256 _price) public onlyOwner {
        require(_price > 0, "Price must be greater than 0");
        mintPriceVKA = _price;
        emit MintPriceUpdated(_price);
    }

    // -- View Functions -- //

    function getMerkleRoot() public view returns (bytes32) {
        return merkleRoot;
    }

    function getSpiritOwned(address _owner) public view returns (uint256[] memory) {
        uint256 bal = balanceOf(_owner);
        uint256[] memory tokens = new uint256[](bal);
        for (uint256 i = 0; i < bal; i++) {
            tokens[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokens;
    }

    //URI section, from ERC721 storage
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721URIStorage: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }

        return super.tokenURI(tokenId);
    }

    function verify(
        bytes32[] memory proof,
        bytes32 leaf
    ) public view returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash < proofElement) {
                computedHash = keccak256(
                    abi.encodePacked(computedHash, proofElement)
                );
            } else {
                computedHash = keccak256(
                    abi.encodePacked(proofElement, computedHash)
                );
            }
        }

        return (computedHash == merkleRoot);
    }

    // -- Minting -- //

    function mintSpirit(bytes32[] memory proof) public nonReentrant {
        uint256 supply = totalSupply();
        require(supply < maxSupply, "All Spirits have been minted");
        require(block.timestamp >= whitelistStartDate, "Whitelist has not started");
        
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));

        (bool isTrue) = verify(proof, leaf);
        require(isTrue, "Merkle proof is not valid");

        uint256 tokenId = _executeMint(msg.sender);
        emit SpiritMinted(msg.sender, tokenId);
    }

    function mintSpiritVKA() public nonReentrant {
        uint256 supply = totalSupply();
        require(supply < maxSupply, "All Spirits have been minted");
        require(block.timestamp >= publicStartDate, "Public mint has not started");

        IERC20Upgradeable(VKA).transferFrom(msg.sender, Treasury, mintPriceVKA);
        uint256 tokenId = _executeMint(msg.sender);
        emit SpiritMinted(msg.sender, tokenId);
    }

    // -- Internal -- //

    function _executeMint(address _to) internal returns (uint256) {
        require(!hasMinted[_to], "You have already minted a Spirit");
        uint256 newItemId = tokenIds;
        _safeMint(msg.sender, newItemId);
        _setTokenURI(newItemId, baseURI);
        tokenIds ++;
        hasMinted[_to] = true;
        return newItemId;
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal {
        require(_exists(tokenId), "ERC721URIStorage: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);

        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }
    }
 
}

