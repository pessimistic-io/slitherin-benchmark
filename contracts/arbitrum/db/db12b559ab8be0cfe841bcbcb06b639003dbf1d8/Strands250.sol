// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC721} from "./ERC721.sol";
import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";
import {DefaultOperatorFilterer} from "./DefaultOperatorFilterer.sol";

error MintLimitReached(uint256 mintLimit);

contract Strands250 is
    ERC721,
    DefaultOperatorFilterer,
    Ownable
{
    uint256 public cap;
    uint256 public mintCounter;
    bool individualize;
    string baseURI;
    uint256 public feeAmount=0;
    address public feeToken;
    address public feeRecipient;

    mapping (uint256 => string) private _tokenURIs;

    constructor(string memory _name,string memory _symbol,uint8 _cap, string memory _baseURI) ERC721(_name, _symbol) {
        cap=_cap;
        baseURI=_baseURI;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory)
    {
        require((mintCounter==0 || tokenId<=mintCounter),"can't get URI for nonexistent token"); 
        if (!individualize) tokenId=1;
        string memory tURI = string(abi.encodePacked(baseURI, _tokenURIs[tokenId]));
        return tURI;
    }

    function setBaseURI(string memory _URI) public onlyOwner {
        baseURI=_URI;
    }

    function setIndividualize(bool i) public onlyOwner {
        individualize = i;
    }

    function setTokenURI(uint256 tokenId, string memory _tokenURI) public onlyOwner {
        require((mintCounter==0 || tokenId<=mintCounter),"can't set URI for nonexistent token");  
        _tokenURIs[tokenId] = _tokenURI;
    }

    function adminSelfBatchMint(
        uint8 num
    ) public onlyOwner {
        for (uint8 i=0;i<num;i++) {
            if (mintCounter >= cap) revert MintLimitReached(mintCounter);
            mintCounter += 1;
            _safeMint(msg.sender, mintCounter);
        }
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public override onlyAllowedOperator(from) {
        require(to != address(0), "INVALID_RECIPIENT");

        if (msg.sender!=owner()) {
            require(
                msg.sender == from || isApprovedForAll[from][msg.sender] || msg.sender == getApproved[id],
                "NOT_AUTHORIZED"
            );
            if (feeAmount>0) ERC20(feeToken).transferFrom(from, feeRecipient, feeAmount);
        }

        unchecked {
            _balanceOf[from]--;
            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }

    function safeTransferFrom(address from, address to, uint256 id) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, id);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes calldata data)
        public
        override
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, id, data);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function setApprovalForAll(address operator, bool approved) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function setFeeRecipient(address _newRecipient) external onlyOwner {
        feeRecipient = _newRecipient;
    }

    function setFeeAmount(uint256 _newAmount) external onlyOwner {
        feeAmount = _newAmount;
    }

    function setFeeToken(address _newToken) external onlyOwner {
        feeToken = _newToken;
    }

}
