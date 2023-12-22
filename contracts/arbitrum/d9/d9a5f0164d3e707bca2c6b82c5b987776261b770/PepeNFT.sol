// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ERC721URIStorage.sol";
import "./Counters.sol";
import "./Ownable.sol";

contract PepeNFT is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    //state varibales
    uint256 public _mintingFee;
    uint256 public _maxMintPerUser;
    uint256 public _totalSupply;

    //keeps track of how many tokens a user has minted
    mapping(address => uint256) public _mintedCount;

    // custom error messages
    string constant INSUFFICIENT_FEE = "Insufficient minting fee";
    string constant INVALID_TOKEN_COUNT = "Invalid number of tokens";

    constructor(
        uint256 mintingFee,
        uint256 maxMintPerUser,
        uint256 totalSupply
    ) ERC721("BOB-PEPE-AI", "BPAI") {
        _mintingFee = mintingFee;
        _maxMintPerUser = maxMintPerUser;
        _totalSupply = totalSupply;
    }

    function batchMint(
        address recipient,
        string memory tokenURI,
        uint256 numberOfTokens
    ) external payable returns (uint256) {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();

        if (
            recipient == address(0) ||
            numberOfTokens == 0 ||
            numberOfTokens > _maxMintPerUser ||
            _mintedCount[msg.sender] + numberOfTokens > _maxMintPerUser
        ) {
            _errorMessage(INVALID_TOKEN_COUNT);
        }

        if (msg.value != numberOfTokens * _mintingFee) {
            _errorMessage(INSUFFICIENT_FEE);
        }

        for (uint256 i = 0; i < numberOfTokens; i++) {
            require(newItemId <= _totalSupply, "Maximum supply mint reached");
            _safeMint(recipient, newItemId);
            _setTokenURI(newItemId, tokenURI);
            newItemId++;
        }
        _mintedCount[msg.sender] += numberOfTokens;

        payable(owner()).transfer(msg.value);

        return newItemId;
    }

    function setMintingFee(uint256 mintingFee) external onlyOwner {
        _mintingFee = mintingFee;
    }

    function setMaxMintPerUser(uint256 maxMintPerUser) external onlyOwner {
        _maxMintPerUser = maxMintPerUser;
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

