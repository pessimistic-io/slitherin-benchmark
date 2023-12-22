// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Counters.sol";

contract PepePunks is ERC721, ERC721Enumerable, Ownable {

    uint public maxSupply = 10000;
    uint public maxFreemint = 5000;
    uint public mintPrice = 1000000000000000;
    uint public claimPerWallet = 1;
    uint public countTotalFreeMint;
    uint public countTotalPublicMint;
    string public baseURI;
    mapping (address => bool) public userFreeMint;
    bool public toggleMint;

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    constructor() ERC721("PEPEPUNKS", "PPUNK") {}

    //FREE MINT

    function FreeMint() public {
        require(toggleMint, "Disabled mint");
        require(countTotalFreeMint+claimPerWallet <= maxFreemint, "Out of Supply");
        require(totalSupply()+claimPerWallet <= maxSupply, "Out of Supply2");
        require(!userFreeMint[msg.sender], "Off limits mint");
        userFreeMint[msg.sender] = true;
        countTotalFreeMint += claimPerWallet;
        for(uint x = 0; x < claimPerWallet; x++){
            _mintItem(msg.sender);
        }
    }

    //MINT

    function Mint(uint _amount) public payable {
        require(toggleMint, "Disabled mint");
        require(_amount > 0, "Amount Invalid");
        require(totalSupply()+_amount <= maxSupply, "Out of Supply2");
        require(msg.value >= _amount*mintPrice, "ETH Insufficient");
        countTotalPublicMint += _amount;
        _toOwner(msg.value);
        for(uint x = 0; x < _amount; x++){
            _mintItem(msg.sender);
        }
    }

    function OwnerMint(uint _amount) public onlyOwner { // Only for GiveAways, Promote
        countTotalFreeMint += _amount;
        for(uint x = 0; x < _amount; x++){
            _mintItem(msg.sender);
        }
    }

    function _mintItem(address _to) internal {
        uint tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(_to, tokenId);
    }

    function _toOwner(uint256 _amount) internal {
        address _owner = owner();
        (bool success, ) = _owner.call{value: _amount}("");
        require(success, "Transfer failed.");
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function walletOfOwner(address _owner) external view returns (uint[] memory) {
        uint tokenCount = balanceOf(_owner);
        uint[] memory tokensId = new uint[](tokenCount);
        for (uint i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokensId;
    }

    //Sets

    function setMintPrice(uint _newPrice) public onlyOwner {
        mintPrice = _newPrice;
    }

    function setClaimPerWallet(uint _newAmount) public onlyOwner {
        claimPerWallet = _newAmount;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function setToggleMint() public onlyOwner {
        toggleMint = !toggleMint;
    }

    function _beforeTokenTransfer(address from, address to, uint tokenId) internal virtual override(ERC721, ERC721Enumerable){
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
