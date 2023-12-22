// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

contract BossCardERC1155Main is ERC1155, Ownable, ReentrancyGuard, Pausable {
    uint public tokensCount = 110;
    mapping(address =>  bool) private _mintApprovals;
    string private _uri;
    mapping(uint256 => string) private _uris;
    constructor(string memory _baseUri) ERC1155(string(
            abi.encodePacked(
                _baseUri,
                "{id}.json"
            )
        )) {
        _uri = _baseUri;
    }

    modifier existId(uint _tokenid) {
        require(_tokenid <= tokensCount, "Invalid token id");
        _;
    }

    modifier existIds(uint[] memory _tokenIds) {
        for(uint i=0; i < _tokenIds.length; i++){
            require(_tokenIds[i] <= tokensCount, "Invalid token id");
        }
        _;
    }

    function setURI(string memory newuri) external onlyOwner {
        _uri = newuri;
    }

    function setTokenUri(uint tokenId_, string memory uri_) external onlyOwner {
        require(bytes(_uris[tokenId_]).length == 0, "Cannot set uri twice");
        _uris[tokenId_] = uri_;
    }

    function setMintApprovalForAll(address operator, bool approved) external {
        _mintApprovals[operator] = approved;
    }

    function isMintApprovedForAll(address operator) public view returns (bool) {
        return _mintApprovals[operator];
    }

    // contract mint function
    function mint(address to, uint tokenId, uint amount) external existId(tokenId){
        require(
            isMintApprovedForAll(msg.sender) || owner() == msg.sender,
            "ERC1155: caller is not owner nor approved"
        );
        _mint(to, tokenId, amount, "");
    }

    function mintBatch(address to, uint[] memory tokenIds, uint[] memory amounts) external existIds(tokenIds) {
        require(
            isMintApprovedForAll(msg.sender) || owner() == msg.sender,
            "ERC1155: caller is not owner nor approved"
        );
        _mintBatch(to, tokenIds, amounts, "");
    }

    function setTokenSize(uint _tokensCount) external onlyOwner{
        tokensCount = _tokensCount;
    }

    function getWalletToken() public view returns(uint[] memory){
        uint256[] memory tokens = new uint256[](tokensCount);
        for(uint256 i = 0; i < tokensCount; i++ ){
            tokens[i] =  balanceOf(msg.sender, i+1);
        }
        return(tokens);
    }

    function uri(uint256 _tokenId) override public view existId(_tokenId) returns (string memory) {
        if(bytes(_uris[_tokenId]).length > 0){
            return _uris[_tokenId];
        }
        return string(
            abi.encodePacked(
                _uri,
                Strings.toString(_tokenId),".json"
            )
        );
    }
}


