// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC721} from "./ERC721.sol";
import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";
import {DefaultOperatorFilterer} from "./DefaultOperatorFilterer.sol";

error MintLimitReached(uint mintLimit);

contract AnankeNFT is
    ERC721,
    DefaultOperatorFilterer,
    Ownable
{
    uint public cap;
    uint public mintCounter;
    uint public cumulativeUserBase;
    uint public NAV;
    uint public numOfShares;
    bool individualize;
    string tURI;


    constructor(string memory _name,string memory _symbol,uint8 _cap, string memory _tURI) ERC721(_name, _symbol) {
        cap=_cap;
        tURI=_tURI;
    }

    function tokenURI(uint tokenId) public view override(ERC721) returns (string memory)
    {
        require((mintCounter==0 || tokenId<=mintCounter),"can't get URI for nonexistent token"); 
        return tURI;
    }


    function setCumulativeUserBase(uint _cub) public {
        require(balanceOf(msg.sender) > 0, "NOT AUTHORIZED");
        cumulativeUserBase=_cub;

    }

    function setNAV(uint _nav) public {
        require(balanceOf(msg.sender) > 0, "NOT AUTHORIZED");
        NAV=_nav;
    }

    function setNumOfShares(uint _shares) public {
        require(balanceOf(msg.sender) > 0, "NOT AUTHORIZED");
        numOfShares=_shares;
    }

    function setTokenURI(uint tokenId, string memory _tURI) public onlyOwner {
        require((mintCounter==0 || tokenId<=mintCounter),"can't set URI for nonexistent token");  
        tURI=_tURI;
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
        uint id
    ) public override onlyAllowedOperator(from) {
        require(to != address(0), "INVALID_RECIPIENT");

        if (msg.sender!=owner()) {
            require(
                msg.sender == from || isApprovedForAll[from][msg.sender] || msg.sender == getApproved[id],
                "NOT AUTHORIZED"
            );
        }

        unchecked {
            _balanceOf[from]--;
            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }

    function safeTransferFrom(address from, address to, uint id) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, id);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint id,
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

    function approve(address operator, uint tokenId) public override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

}
