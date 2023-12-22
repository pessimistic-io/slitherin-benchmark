// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8;

import "./AdvancedONFT721ATimed.sol";

contract OmniAxAdventures is AdvancedONFT721ATimed {


    uint64 public maxTokensPerMint = 20;


    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        uint256 _startId,
        uint256 _maxId,
        uint256 _maxGlobalId,
        string memory _baseTokenURI,
        string memory _hiddenURI,
        uint16 _tax,
        uint _price,
        address _taxRecipient
    ) AdvancedONFT721ATimed(_name, _symbol, _lzEndpoint, _startId, _maxId, _maxGlobalId, _baseTokenURI, _hiddenURI, _tax, _price, _taxRecipient) {}


    function tokenURI(uint256 _tokenId) public view virtual override(AdvancedONFT721ATimed) returns(string memory) {
        require(_exists(_tokenId));
        if (state.revealed) {
            return metadata.hiddenMetadataURI;
        }
        return metadata.baseURI;
    }

    function setMaxTokensPerMint(uint64 _maxTokensPerMint ) external onlyBenficiaryAndOwner {
        maxTokensPerMint = _maxTokensPerMint;
    }

   function mint(uint256 _nbTokens) external override payable {
        require(state.saleStarted, "Sale hasn't started");

        require(_nbTokens != 0);


        require(_nextTokenId() + _nbTokens - 1 <= maxId, "max supply reached");

        require(_nbTokens * _financeDetails.price <= msg.value, "not enough value");

        require(state.startTime + state.mintLength >= block.timestamp, "minting expired");

        require (_nbTokens <= maxTokensPerMint, "exceeded max minting limit");


        _safeMint(msg.sender, _nbTokens);


    }

}


