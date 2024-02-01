// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./MerkleProof.sol";
import "./Strings.sol";
import "./ERC721AUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./DefaultOperatorFiltererUpgradeable.sol";


//author = atak.eth
contract souvenirTest is  ERC721AUpgradeable, DefaultOperatorFiltererUpgradeable,
    OwnableUpgradeable {
    
    string baseURI;
    address public minterContract;    
    
    function initialize(string memory name, string memory symbol) initializerERC721A initializer public {

        __ERC721A_init(name, symbol);
        __Ownable_init();
        __DefaultOperatorFilterer_init();
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function mint(address _to) public {
        require(msg.sender == minterContract,"You aren't the minter contract.");
        _mint(_to, 1);
    }

    function setMinterRole(address _minterAddress) public onlyOwner {
        minterContract = _minterAddress;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory){
        return string(abi.encodePacked(baseURI, Strings.toString(tokenId), ".json"));
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function transferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }


}

   

