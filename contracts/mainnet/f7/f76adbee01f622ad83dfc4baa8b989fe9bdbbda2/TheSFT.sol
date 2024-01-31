// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./ERC1155Supply.sol";
import "./Strings.sol";

contract TheSFT is ERC1155, Ownable, ERC1155Supply {

    mapping(uint => uint) public Minted; 
    mapping(uint => uint) public Limits;
    string private ext;
    string public baseURI;
    
    address public manager;

    constructor(address _manager) ERC1155("") {
        Limits[0] = 10000;
        Limits[1] = 10000;
        Limits[2] = 10000;
        Limits[3] = 100;
        Limits[4] = 50;
        setManager(_manager);
        ext = '.json';
    }

    modifier onlyOwnerOrManager() {
        require(msg.sender == owner() || msg.sender == manager , "Not owner or manager ");
        _;
    }
    

    function setManager(address _addr) public onlyOwner {
        manager = _addr;
    }

    

    function setExtention(string calldata _ext) external onlyOwnerOrManager {
        ext = _ext;
    }
    function setBaseURI(string memory _baseURI_) public onlyOwnerOrManager {
        baseURI = _baseURI_;
    }

    


    function _baseURI() internal view returns (string memory){
        return baseURI;
    }

    function uri(uint256 _tokenId) public view virtual override returns (string memory) {
        require(_tokenId < 5, "URI query for nonexistent token");
        return string(abi.encodePacked(_baseURI(), Strings.toString(_tokenId), ext));
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data)
        public
        onlyOwnerOrManager
    {
        require(id< 5 && id>=0, "only 0-5");

        Minted[id] += amount;
        require(Minted[id] < Limits[id], "no more mint");

        _mint(account, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        onlyOwner
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
}
