// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./Ownable.sol";
import "./ERC721.sol";
import "./ReentrancyGuard.sol";
import "./Strings.sol";

import "./console.sol";

contract BlessedVillagers is ERC721, Ownable, ReentrancyGuard {
    
    string public baseUri = "ipfs://QmNxh959di3qS3FXVDNFGcH15sfG15gtJLVJFPAAPhYVWu/";

    address public initationContract;

    bool public permDisabled = false;

    constructor() ERC721("Blessed Villager", "BLESSV") {

    }

    function airdrop(address[] calldata _addresses, uint256[] calldata tokenIds) public onlyOwner {
        require(!permDisabled, "Minting is disabled forever");

        for(uint256 i = 0; i < _addresses.length; i++)
            _mint(_addresses[i], tokenIds[i]);
        
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {

		return string(abi.encodePacked(baseUri, Strings.toString(tokenId), ".json"));
	}

    function setBaseUri(string memory uri) public onlyOwner {
        baseUri = uri;
    }

    function disableMintForever() public onlyOwner {
        permDisabled = true;
    }

    function withdraw() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call {value: address(this).balance}("");
        require(success);
    }

    function setInitiationContract(address _initationContract) public onlyOwner {
        initationContract = _initationContract;
    }

    function setApprovalForAll(address operator, bool approved) public override {
        require(operator == initationContract, "Only the initation contract can be approved");

        super.setApprovalForAll(operator, approved);
    }

    function _beforeTokenTransfer(address from, address, uint256, uint256) internal override {
        
        if(msg.sender == initationContract) return;

        if(from == address(0)) return;

        revert("Transfers are disabled for this contract");

    }

}

