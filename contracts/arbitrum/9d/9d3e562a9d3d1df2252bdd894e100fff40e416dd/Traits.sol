// SPDX-License-Identifier: GPL-3.0
//author: Johnleouf21
pragma solidity 0.8.19;
import "./ERC1155.sol";
import "./Ownable.sol";
import "./AccessControlEnumerable.sol";
import "./ERC1155Supply.sol";
import "./Strings.sol";
import "./Tsan.sol";
import "./TamagoSan.sol";

contract Traits is ERC1155, Ownable, AccessControlEnumerable, ERC1155Supply{

    using Strings for uint256;

    mapping(address => bool) admins;

    Tsan public tsan = Tsan(address(0xa247122da0a980dDf69b22f0f0C311cd2851a8F4));

    string _baseURI = "https://tamagosan-server.fra1.cdn.digitaloceanspaces.com/traitMetadata/";

    constructor() ERC1155(""){
    }

    function addAdmin(address _admin) external onlyOwner {
        admins[_admin] = true;
    }

    function setTsanAddress(address _newTsanAddress) external onlyOwner {
    tsan = Tsan(_newTsanAddress);
    }

    function mint(address to,uint256 tokenID) public onlyOwner {
        _mint(to, tokenID, 1,'');
    }

    function externalMint(address to, uint256 tokenID) external {
        require(admins[msg.sender], "Cannot mint if not admin");
        _mint(to, tokenID, 1,'');
    }

    function editBatchTransfer(address from,address to,uint256[] memory traitIDs) public {
        uint256[] memory amounts = new uint256[](traitIDs.length);
        for(uint i = 0;i<traitIDs.length;i++){
            amounts[i] = 1;
        }
        safeBatchTransferFrom(from, to, traitIDs, amounts, "");
    }

    function burn (address to, uint tokenID, uint amount) public {
        _burn(to, tokenID, amount);
    }

    function uri(uint256 tokenID) public view virtual override returns (string memory) {
        return string(abi.encodePacked(_baseURI,tokenID.toString(),".json"));
    }

    function _beforeTokenTransfer(
        address operator, 
        address from, 
        address to, 
        uint256[] memory ids, 
        uint256[] memory amounts, 
        bytes memory data
    )
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControlEnumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance; // get the balance of the smart contract
        payable(msg.sender).transfer(balance);
    }

    function getBalance() public view onlyOwner returns (uint256) {
        return address(this).balance;
    }

}
