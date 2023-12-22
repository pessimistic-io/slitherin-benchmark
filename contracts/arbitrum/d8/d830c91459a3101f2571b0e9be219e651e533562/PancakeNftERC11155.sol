// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;

import "./ERC1155.sol";
import "./ERC1155Burnable.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

contract PancakeNftERC11155 is ERC1155, ERC1155Burnable,ReentrancyGuard, Ownable, Pausable {
    uint public tokensCount = 19;
    string private _uri;
    mapping(address =>  bool) private _mintApprovals;

    constructor(string memory _baseUri) ERC1155(string(
            abi.encodePacked(
                _baseUri,
                "{id}.json"
            )
        )) {
        _uri = _baseUri;
    }

    modifier existId(uint _tokenid) {
        require(_tokenid <= tokensCount, "Invalid token id");
        _;
    }

    modifier existIds(uint[] memory _tokenIds) {
        for(uint i=0; i < _tokenIds.length; i++){
            require(_tokenIds[i] <= tokensCount, "Invalid token id");
        }
        _;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setURI(string memory newuri) external onlyOwner {
        _uri = newuri;
    }

    function setMintApprovalForAll(address operator, bool approved) external onlyOwner{
        _mintApprovals[operator] = approved;
    }

    function isMintApprovedForAll(address operator) public view returns (bool) {
        return _mintApprovals[operator];
    }

    // contract mint function
    function mint(address to, uint tokenId, uint amount) external existId(tokenId){
        require(
            isMintApprovedForAll(msg.sender) || owner() == msg.sender,
            "ERC1155: caller is not owner nor approved"
        );
        _mint(to, tokenId, amount, "");
    }

    function mintBatch(address to, uint[] memory tokenIds, uint[] memory amounts) external existIds(tokenIds) {
        require(
            isMintApprovedForAll(msg.sender) || owner() == msg.sender,
            "ERC1155: caller is not owner nor approved"
        );
        _mintBatch(to, tokenIds, amounts, "");
    }

    function getWalletToken() external view returns(uint[] memory){
        uint256[] memory tokens = new uint256[](tokensCount);
        for(uint256 i = 0; i < tokensCount; i++ ){
            tokens[i] =  balanceOf(msg.sender, i+1);
        }
        return(tokens);
    }

    function uri(uint256 _tokenId) override public view existId(_tokenId) returns (string memory) {
        return string(
            abi.encodePacked(
                _uri,
                Strings.toString(_tokenId),".json"
            )
        );
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
