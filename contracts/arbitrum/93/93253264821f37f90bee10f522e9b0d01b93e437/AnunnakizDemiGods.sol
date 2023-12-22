// SPDX-License-Identifier: MIT
// Author: Gulshan Jubaed Prince - jubaedprince@gmail.com

pragma solidity ^0.8.4;

import "./ERC1155.sol";
import "./AccessControl.sol";
import "./Strings.sol";
import "./ERC1155Supply.sol";

contract AnunnakizDemiGods is ERC1155, AccessControl, ERC1155Supply {
    bytes32 public constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public currentTokenId;
    int public edition;
    bool public publicMint;

    constructor() ERC1155("https://anunnakiz.s3.amazonaws.com/metadata/{id}.json") {
        currentTokenId = 1;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(URI_SETTER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        publicMint = false;
        edition = 1;
    }

    function uri(uint256 _tokenId) override public view returns (string memory) {
        return string(
            abi.encodePacked(
            "https://anunnakiz.s3.amazonaws.com/metadata/",
            Strings.toString(_tokenId),
            ".json"
           )
        );
    }

    function turnOnPublicMint() public onlyRole(DEFAULT_ADMIN_ROLE) {
        publicMint = true;
    }

    function setURI(string memory newuri) public onlyRole(URI_SETTER_ROLE) {
        _setURI(newuri);
    }

    function withdraw() public payable onlyRole(DEFAULT_ADMIN_ROLE)  {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success);
    }

    function whiteListMint() public payable onlyRole(MINTER_ROLE) 
    {
        require(msg.value == 0.04 ether, "Price must be 0.04 arbitrum eth");
        _processMint();
    }

    function mint() public payable
    {
        require(publicMint == true, "Public mint has not started yet.");
        require(msg.value == 0.04 ether, "Price must be 0.04 arbitrum eth");
        _processMint();
    }

    function adminMint() public onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _processMint();
    }

    function _processMint() internal{
        if(currentTokenId > 33){
            edition++;
            currentTokenId = 1;
        }

        if(edition < 4){
            _mint(msg.sender, currentTokenId, 1, "");
            currentTokenId++;
        }
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _mintBatch(to, ids, amounts, data);
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
