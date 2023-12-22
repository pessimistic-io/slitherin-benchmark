// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721.sol";
import "./Ownable.sol";
import "./ERC721Enumerable.sol";

contract MCMXII is ERC721, ERC721Enumerable, Ownable {
    uint128 public constant MAX_SUPPLY = 1912;
    uint128 public constant PUBLIC_SUPPLY = 912;

    string private _baseURIextended;

    bool public publicActive = false;
    bool public listActive = false;

    mapping(address => uint8) private _list;

    constructor() ERC721("1912", "MGMB") {
    }

    function setActive(uint8 _mode) external onlyOwner {
        if (_mode % 10 != 0) {
            publicActive = true;
        } else {
            publicActive = false;
        }
        if ((_mode % 100) /10 != 0) {
            listActive = true;
        } else {
            listActive = false;
        }
    }

    function mint() public payable {
        uint256 supply = totalSupply();
        require(publicActive, "Sorry you can't mint now");
        require(supply < PUBLIC_SUPPLY, "SOLD OUT");
        uint256 _tokenId = supply + 1;
        _safeMint(msg.sender, _tokenId);
    }
    function setList(address[] calldata addresses, uint8 numAllowedToMint) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            _list[addresses[i]] = numAllowedToMint;
        }
    }

    function numAvailableToMint(address addr) external view returns (uint8) {
        return _list[addr];
    }

    function mintAllowList(uint8 numberOfTokens) external payable {
        uint256 supply = totalSupply();
        require(listActive, "Sorry you can't mint now");
        require(numberOfTokens <= _list[msg.sender], "The number available for purchase is exceeded");
        require(supply + numberOfTokens <= MAX_SUPPLY, "It's going to be over 1912");
        _list[msg.sender] -= numberOfTokens;
        uint256 _tokenId = supply + 1;
        for (uint256 i = 0; i < numberOfTokens; i++) {
            _safeMint(msg.sender, _tokenId + i);
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function setBaseURI(string memory baseURI_) external onlyOwner() {
        _baseURIextended = baseURI_;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIextended;
    }

    function reserveMint(uint256 num) public onlyOwner {
      uint256 supply = totalSupply();
      uint256 _tokenId = supply + 1;
      for (uint256 i = 0; i < num; i++) {
          _safeMint(msg.sender, _tokenId + i);
      }
    }

    function withdraw() public onlyOwner {
        uint balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }
}
