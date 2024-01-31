// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./MerkleProof.sol";

/*
██████╗░██╗░░░██╗██████╗░██████╗░██╗░░░░░███████╗  ██████╗░██╗░░░░░░█████╗░███╗░░██╗███████╗████████╗░██████╗
██╔══██╗██║░░░██║██╔══██╗██╔══██╗██║░░░░░██╔════╝  ██╔══██╗██║░░░░░██╔══██╗████╗░██║██╔════╝╚══██╔══╝██╔════╝
██████╦╝██║░░░██║██████╦╝██████╦╝██║░░░░░█████╗░░  ██████╔╝██║░░░░░███████║██╔██╗██║█████╗░░░░░██║░░░╚█████╗░
██╔══██╗██║░░░██║██╔══██╗██╔══██╗██║░░░░░██╔══╝░░  ██╔═══╝░██║░░░░░██╔══██║██║╚████║██╔══╝░░░░░██║░░░░╚═══██╗
██████╦╝╚██████╔╝██████╦╝██████╦╝███████╗███████╗  ██║░░░░░███████╗██║░░██║██║░╚███║███████╗░░░██║░░░██████╔╝
╚═════╝░░╚═════╝░╚═════╝░╚═════╝░╚══════╝╚══════╝  ╚═╝░░░░░╚══════╝╚═╝░░╚═╝╚═╝░░╚══╝╚══════╝░░░╚═╝░░░╚═════╝░
*/

contract BubblePlanets is ERC721A, Ownable {
    using SafeMath for uint256;

    bytes32 public merkleRoot = 0x80f19c31690593b71c969e320379d82784cad068ee0b722a1837557e32429ed5;

    bool public revealed = false;
    bool public mintActive = false;
    bool public whitelistMintActive = false;

    string public baseURI = '';
    string public nonRevealURI= 'https://bubble-planets.nyc3.digitaloceanspaces.com/reveal/json/';

    uint256 public price = 0.0044 ether;
    uint256 public whitelistPrice = 0.0022 ether;
    uint256 public mintLimit = 1;
    uint256 public maxSupply = 555;

    constructor() ERC721A("Bubble Planets", "BP") {}

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        if (!revealed) {
            return bytes(nonRevealURI).length != 0 ? string(abi.encodePacked(nonRevealURI, _toString(tokenId), '.json')) : '';
        }

        return bytes(baseURI).length != 0 ? string(abi.encodePacked(baseURI, _toString(tokenId), '.json')) : '';
    }

    function mint(uint256 quantity) external payable {
        require(mintActive, "The mint is not active.");
        require(totalSupply().add(quantity) <= maxSupply, "The requested mint quantity exceeds the supply.");
        require(_numberMinted(msg.sender).add(quantity) <= mintLimit, "The requested mint quantity exceeds the mint limit.");
        require(price.mul(quantity) <= msg.value, "Not enough ETH for mint transaction.");

        _mint(msg.sender, quantity);
    }

    function whitelistMint(uint256 quantity, bytes32[] calldata merkleProof) external payable {
        require(whitelistMintActive, "The whitelist mint is not active.");
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(merkleProof, merkleRoot, leaf), "Invalid merkle proof.");
        require(totalSupply().add(quantity) <= maxSupply, "The requested mint quantity exceeds the supply.");
        require(_numberMinted(msg.sender).add(quantity) <= mintLimit, "The requested mint quantity exceeds the mint limit.");
        require(whitelistPrice.mul(quantity) <= msg.value, "Not enough ETH for mint transaction.");

        _mint(msg.sender, quantity);
    }

    function airdrop(address[] memory _addresses) external onlyOwner {
        require(totalSupply().add(_addresses.length) <= maxSupply, "The requested mint quantity exceeds the supply.");

        for (uint256 i = 0; i < _addresses.length; i++) {
            _mint(_addresses[i], 1);
        }
    }

    function mintTo(uint256 _quantity, address _receiver) external onlyOwner {
        require(totalSupply().add(_quantity) <= maxSupply, "The requested mint quantity exceeds the supply.");
        _mint(_receiver, _quantity);
    }

    function fundsWithdraw() external onlyOwner {
        uint256 funds = address(this).balance;
        require(funds > 0, "Insufficient balance.");

        (bool status,) = payable(msg.sender).call{value : funds}("");
        require(status, "Transfer failed.");
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setRevealed(bool _revealed) external onlyOwner {
        revealed = _revealed;
    }

    function setMintActive(bool _mintActive) external onlyOwner {
        mintActive = _mintActive;
    }

    function setWhitelistMintActive(bool _whitelistMintActive) external onlyOwner {
        whitelistMintActive = _whitelistMintActive;
    }

    function setBaseUri(string memory _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    function setNonRevealUri(string memory _nonRevealURI) external onlyOwner {
        nonRevealURI = _nonRevealURI;
    }

    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    function setWhitelistPrice(uint256 _whitelistPrice) external onlyOwner {
        whitelistPrice = _whitelistPrice;
    }

    function setMintLimit(uint256 _mintLimit) external onlyOwner {
        mintLimit = _mintLimit;
    }

    function setMaxSupply(uint256 _maxSupply) external onlyOwner {
        maxSupply = _maxSupply;
    }
}

