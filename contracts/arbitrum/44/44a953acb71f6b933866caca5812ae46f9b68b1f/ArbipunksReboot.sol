// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "./ERC721.sol";

contract ArbipunksReboot is ERC721 {
    using Strings for uint256;
    string public constant base =
        "ipfs://QmPw2vVcZx6kQjNc1Dbu7sYmV4jQ8bmiopWdbU3Tve7hDn/";
    uint256 private s_tokenCounter;
    uint256 private s_newTokenCounter;
    IERC721 private original = IERC721(0x4772fB92e6606c87f7cDDcCDB880f7677768815c);
    address private marketingTeam = 0x54a8C5CF7149C067F8Cd7653Afa0af599B0f1fCf;

    constructor() ERC721("ArbiPunks Reboot", "APUNKSREBOOT") {
        s_tokenCounter = 0;
        s_newTokenCounter = 10000;
    }

    // Mint for free if you own the rugged token.
    function mintNft(uint tokenId) public {
        require(original.ownerOf(tokenId) == msg.sender, "Caller must own the original token.");
        s_tokenCounter = s_tokenCounter + 1;
        _safeMint(msg.sender, tokenId);
    }

    // Mint additional Punks at a premium.
    function mintNftWithFee() public payable{
        require(s_newTokenCounter <= 10999, "Token must be <= 10999.");
        require(msg.value == 0.05 ether, "You must pay 0.05 ETH to mint.");
        s_newTokenCounter = s_newTokenCounter + 1;
        _safeMint(msg.sender, s_newTokenCounter);
    }

    function withdraw() external{
        require(msg.sender == marketingTeam);
        (bool sent,) = payable(msg.sender).call{value: address(this).balance}("");
        require(sent);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return string(abi.encodePacked(base, tokenId.toString(), ".json"));
    }

    function getTokenCounter() public view returns (uint256) {
        return s_tokenCounter;
    }

    function getNewTokenCounter() public view returns (uint256) {
        return s_newTokenCounter;
    }

    function totalSupply() public view returns(uint256){
        return 11000;
    }
}

