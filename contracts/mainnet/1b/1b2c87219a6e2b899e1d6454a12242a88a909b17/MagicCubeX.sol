// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./Ownable.sol";
import "./ERC721.sol";

contract MagicCubeX is Ownable, ERC721 {

    using Strings for uint256;

    bool public isOpen = false;

    uint256 public constant TOTAL_MAX_QTY = 2222;
    address public MagicCubeAddress = 0xCE84b062da253d40D6FF8a430C9Fa69C6F9F9CAf;
    
    string private _tokenURI;
    uint256 public totalSupply;

    constructor(
        string memory tokenURI_
    ) ERC721("Magic Cube X", "Magic Cube X") {
        _tokenURI = tokenURI_;
    }

    function holderMint(address sender) external {
        require(msg.sender == MagicCubeAddress, "Can't mint!");
        _safeMint(sender, totalSupply + 1);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        string memory baseURI = _baseURI();
        if (!isOpen) {
            return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI)) : "";
        } else {
            return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
        }
    }

    function setIsOpen(bool isOpen_) external onlyOwner {
        isOpen = isOpen_;
    }

    function setTokenURI(string memory tokenURI_) external onlyOwner {
        _tokenURI = tokenURI_;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _tokenURI;
    }
}

