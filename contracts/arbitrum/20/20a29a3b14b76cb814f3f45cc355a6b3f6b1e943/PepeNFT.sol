// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ERC721URIStorage.sol";
import "./Counters.sol";
import "./Ownable.sol";

contract PepeNFT is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    //state varibales
    uint256 public _maxMintAdmin;
    uint256 public _totalSupply;

    //keeps track of how many tokens a user has minted
    mapping(address => uint256) public _mintedCount;

    // custom error messages
    string constant INVALID_TOKEN_COUNT = "Invalid number of tokens";

    constructor(
        uint256 maxMintAdmin,
        uint256 totalSupply
    ) ERC721("BOB-PEPE-AI", "BPAI") {
        _maxMintAdmin = maxMintAdmin;
        _totalSupply = totalSupply;
    }

    function batchMint(
        address recipient,
        string memory tokenURI,
        uint256 numberOfTokens
    ) external onlyOwner returns (uint256) {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();

        if (
            recipient == address(0) ||
            numberOfTokens == 0 ||
            numberOfTokens > _maxMintAdmin ||
            _mintedCount[msg.sender] + numberOfTokens > _maxMintAdmin
        ) {
            _errorMessage(INVALID_TOKEN_COUNT);
        }

        for (uint256 i = 0; i < numberOfTokens; i++) {
            require(newItemId <= _totalSupply, "Maximum supply mint reached");
            _safeMint(recipient, newItemId);
            _setTokenURI(newItemId, tokenURI);
            newItemId++;
        }
        _mintedCount[msg.sender] += numberOfTokens;

        return newItemId;
    }

    function setMaxMintAdmin(uint256 maxMintAdmin) external onlyOwner {
        _maxMintAdmin = maxMintAdmin;
    }

    function setTotalSupply(uint256 totalSupply) external onlyOwner {
        _totalSupply = totalSupply;
    }

    function _errorMessage(
        string memory message
    ) private pure returns (string memory) {
        revert(message);
    }
}

