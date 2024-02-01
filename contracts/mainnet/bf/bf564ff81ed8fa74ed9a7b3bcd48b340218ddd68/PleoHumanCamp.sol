// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./ERC721.sol";
// import {LicenseVersion, CantBeEvil} from "@a16z/contracts/licenses/CantBeEvil.sol";
import "./ERC2981.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./PleoSynthVotesToken.sol";
import "./ERC721Enumerable.sol";



contract PleoHumanCamp is ERC721Enumerable,ERC2981,Ownable, ReentrancyGuard,PleoSynthVotesToken {
    uint96  private _royaltyFraction = 500;
    uint256 private _maxPerAddr = 1;
    string private _tokenUri = "";
    address[] private _checkCampAddr;
    mapping(address => uint256) private _accountTokens;

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    constructor(string memory tokenUri,address[] memory checkCampAddr,address pleoSynthVotes)
     ERC721("pleo-HumanCamp", "pleo-HumanCamp")  PleoSynthVotesToken(pleoSynthVotes) {
        _tokenUri = tokenUri;
        _checkCampAddr = checkCampAddr;
    }

    

    function mint() external {
        for(uint256 i=0;i<_checkCampAddr.length;i++) {
            require(ERC721(_checkCampAddr[i]).balanceOf(_msgSender()) < 1, "Each address can only join one camp!");
        }
        require(balanceOf(_msgSender()) < _maxPerAddr,'Max supply for this address exceeded!');
        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();
        _safeMint(_msgSender(),tokenId,"");
        _setTokenRoyalty(tokenId,owner(),_royaltyFraction);
    }

    

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721Enumerable,ERC2981) returns (bool) {
        return 
            ERC721Enumerable.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    function burn(uint256 tokenId) public {
        _burn(tokenId);
        _resetTokenRoyalty(tokenId);
    }

    function burnMySelf() public {
        uint256 total = balanceOf(_msgSender());
        for(uint256 i=0;i<total;i++) {
            uint256 tokenId = tokenOfOwnerByIndex(_msgSender(), i);
            burn(tokenId);
        }
    }

    function setMaxPerAddr(uint256 maxPerAddr) public onlyOwner {
        _maxPerAddr = maxPerAddr;
    }

    function setTokenUri(string memory tokenuri) public onlyOwner {
        _tokenUri = tokenuri;
    }

    function setRoyaltyFraction(uint96 royaltyFraction) public onlyOwner {
        _royaltyFraction = royaltyFraction;
    }

    function setCheckCampAddr(address[] memory checkCampAddr) public onlyOwner {
        _checkCampAddr = checkCampAddr;
    }
    

    function getTokenUri() public view returns(string memory) {
        return _tokenUri;
    }

    function getRoyaltyFraction() public view returns(uint96) {
        return _royaltyFraction;
    }

    function getCheckCampAddr() public view returns(address[] memory) {
        return _checkCampAddr;
    }


    function _afterTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super.transferVotingUnits(from, to, batchSize);
        super._afterTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function balanceOf(address account) public view override(ERC721,IERC721,PleoSynthVotesToken) returns(uint256) {
        return super.balanceOf(account);
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        return _tokenUri;
    }
}
