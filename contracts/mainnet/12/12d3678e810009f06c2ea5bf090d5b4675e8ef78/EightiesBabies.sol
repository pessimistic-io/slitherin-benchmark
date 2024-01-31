//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.15;

import "./Owned.sol";
import "./ERC721A.sol";
import "./Strings.sol";

contract EightiesBabies is ERC721A, Owned {
    using Strings for uint256;

    string public baseURI;
    bool public mintActive;
    uint public maxSupply = 1e4;
    uint public mintPrice = 8e16;

    constructor()ERC721A("Eighties Babies", "8B")Owned(msg.sender){}

    function mint(uint amount) external payable {
        require(mintActive, "Minting is not active");
        require(msg.value >= mintPrice * amount, "Insufficient payment");
        require(totalSupply() + amount <= maxSupply, "Max supply reached");
        _safeMint(msg.sender, amount);
    }

    function executiveBurn(uint tokenId) external onlyOwner {
        _burn(tokenId);
    }

    function updateBaseURI(string calldata newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
    }

    function flipMintActive() external onlyOwner {
        mintActive = !mintActive;
    }

    function updateMintPrice(uint newMintPrice) external onlyOwner {
        mintPrice = newMintPrice;
    }

    function tokenURI(uint tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "This token does not exist");
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    function withdraw() external onlyOwner {
        assembly {
            let result := call(0, caller(), selfbalance(), 0, 0, 0, 0)
            switch result
            case 0 { revert(0, 0) }
            default { return(0, 0) }
        }
    }
}
