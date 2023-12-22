// SPDX-License-Identifier: MIT

/**
 * Author: @jupiter229
 * Github: https://github.com/jupiter229
 */

pragma solidity ^0.8.16;

import "./ERC721.sol";
import "./Counters.sol";
import "./Ownable.sol";

contract ARBOSHIS is ERC721, Ownable {
    using Strings for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private _supply;

    string private baseURI;

    // Total supply
    uint256 public constant MAX_SUPPLY = 200;

    // Public mint constants
    uint256 private _mintPrice = 0.1 ether;

    bool private _locked = false; // for re-entrancy guard

    uint16[9999] public ids;

    uint16 private index;

    // Initializes the contract by setting a `name` and a `symbol`
    constructor(string memory _initBaseURI) ERC721("ARBOSHIS", "ANNOY") {
        setBaseURI(_initBaseURI);

        for (uint256 i = 10; i != 0; ) {
            unchecked{ --i; }
            uint256 _random = uint256(keccak256(abi.encodePacked(index, msg.sender, block.timestamp, blockhash(block.number-1))));
            _safeMint(msg.sender, _pickRandomUniqueId(_random));
            _supply.increment();
        }
    }

    // Get total supply
    function totalSupply() public view returns (uint256) {
        return _supply.current();
    }

    // Base URI
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    // Set base URI
    function setBaseURI(string memory _newBaseURI) public {
        baseURI = _newBaseURI;
    }

    // Get metadata URI
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token.");

        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(abi.encodePacked(currentBaseURI, tokenId.toString()))
                : "";
    }

    // Mint function
    function mint(uint256 quantity) external payable {
        require(!_locked, "Re-entrancy guard is in effect");

        require(totalSupply() + quantity <= MAX_SUPPLY, "Exceeded maximum token supply");

        require(msg.value >= _mintPrice * quantity, "Insufficient ether sent");

        _locked = true;

        for (uint256 i = quantity; i != 0; ) {
            unchecked{ --i; }
            uint256 _random = uint256(keccak256(abi.encodePacked(index, msg.sender, block.timestamp, blockhash(block.number-1))));
            _safeMint(msg.sender, _pickRandomUniqueId(_random));
            _supply.increment();
        }

        _locked = false;
    }


    // Set randon number
    function _pickRandomUniqueId(uint256 random) private returns (uint256 id) {
        unchecked{ ++index; }
        uint256 len = ids.length - index;
        require(len != 0, 'no ids left');
        uint256 randomIndex = random % len;
        id = ids[randomIndex] != 0 ? ids[randomIndex] : randomIndex;
        ids[randomIndex] = uint16(ids[len - 1] == 0 ? len - 1 : ids[len - 1]);
        ids[len - 1] = 0;
    }

    // Set mint price
    function setMintPrice(uint256 _newMintPrice) external onlyOwner {
        _mintPrice = _newMintPrice;
    }

    // Withdraw balance
    function withdraw() external onlyOwner {
        require(!_locked, "Re-entrancy guard is in effect");

        _locked = true;

        // Transfer the remaining balance to the owner
        (bool sent, ) = payable(owner()).call{ value: address(this).balance }("");
        require(sent, "Failed to withdraw Ether.");

        _locked = false;
    }

    // Receive any funds sent to the contract
    receive() external payable {}
}

