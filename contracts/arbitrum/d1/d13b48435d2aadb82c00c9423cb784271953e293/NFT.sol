// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC721} from "./ERC721.sol";
import {Auth, Authority} from "./Auth.sol";
import {String} from "./String.sol";

contract NFT is ERC721, Auth {
    using String for uint256;

    string public baseURI;

    uint256 public totalSupply;
    uint256 public maxSupply;
    uint256 public transferFee;

    // We allow for internal tiers of tokens to be minted.
    // This can be used to calculate different mint prices for different tiers.
    // This can be side-stepped by always using tierId 0 and not setting maxTierSupply.
    uint256 public tierCount;

    mapping(uint256 tier => uint256 maxSupply) public maxTierSupply;
    mapping(uint256 tier => uint256 supply) public tierMintCount;
    mapping(uint256 tokenId => uint256 tier) public tierOf;

    event SetTransferFee(uint256 transferFee);
    event SetTierSupply(uint256 indexed tier, uint256 maxSupply);
    event SetBaseURI(string baseURI);
    event SetMaxSupply(uint256 maxSupply);

    constructor(
        string memory _name,
        string memory _symbol,
        address _owner,
        address _authority,
        string memory _baseTokenURI,
        uint256 _maxSupply,
        uint256 _transferFee
    ) ERC721(_name, _symbol) Auth(_owner, Authority(_authority)) {
        baseURI = _baseTokenURI;
        maxSupply = _maxSupply;
        transferFee = _transferFee;
        emit SetBaseURI(_baseTokenURI);
        emit SetMaxSupply(_maxSupply);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(tokenId < totalSupply, "URI query for nonexistent token");
        return string.concat(baseURI, tokenId.uint2str());
    }

    function getTransferFee(uint256) external view returns (uint256) {
        return transferFee;
    }

    function transferFrom(address from, address to, uint256 id) public payable virtual override {
        require(msg.value >= transferFee, "Insufficient transfer fee");
        super.transferFrom(from, to, id);
    }

    function setTransferFee(uint256 _fee) external requiresAuth {
        transferFee = _fee;
        emit SetTransferFee(_fee);
    }

    // Set max supply for new or existing tier.
    // Once a tier is added it cannot be removed.
    function setTierSupply(uint256 tier, uint256 supply) external requiresAuth {
        require(tier <= tierCount, "Invalid group id");
        if (tier == tierCount) {
            // We are adding a new tier.
            tierCount++;
        }
        maxTierSupply[tier] = supply;
        emit SetTierSupply(tier, supply);
    }

    function setBaseURI(string memory _baseURI) external requiresAuth {
        baseURI = _baseURI;
        emit SetBaseURI(_baseURI);
    }

    function setMaxSupply(uint256 _maxSupply) external requiresAuth {
        maxSupply = _maxSupply;
        emit SetMaxSupply(_maxSupply);
    }

    function mint(address to, uint256 tier) external requiresAuth returns (uint256 tokenId) {
        require(totalSupply < maxSupply, "Max supply reached");
        if (tierCount > 0) {
            require(tier < tierCount, "Invalid tier");
            require(tierMintCount[tier] < maxTierSupply[tier], "Max group supply reached");
        }
        tokenId = totalSupply++;
        tierMintCount[tier]++;
        _mint(to, tokenId);
    }

    function burn(uint256 tokenId) external {
        require(msg.sender == ownerOf(tokenId), "Not owner of");
        _burn(tokenId);
    }

    function collectFees() external requiresAuth {
        (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
}

