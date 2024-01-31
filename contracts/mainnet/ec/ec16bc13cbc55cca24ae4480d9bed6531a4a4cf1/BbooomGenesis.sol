// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ERC721.sol";
import "./Ownable.sol";
import "./DefaultOperatorFilterer.sol";

contract BbooomGenesis is ERC721,Ownable,DefaultOperatorFilterer {


  // Constants
    uint256 public  MINT_PRICE = 59000000000000000;
    bool public MINT_STATUS = false;
    mapping(address => uint) buyLimitList;
    uint constant public TOKEN_LIMIT = 5300;
    uint[TOKEN_LIMIT]  indices;
    uint  nonce;
    uint  index;
    struct drop_data{
        address drop_address;
        uint256 tokenId; 
    }

  /// @dev Base token URI used as a prefix by tokenURI().
  string public baseTokenURI;

    constructor() ERC721("BBOOOM_Genesis", "BBOOOM_Genesis") {
          baseTokenURI = "ipfs://bafybeigfv5mw3bo72hepzl7bl57rcp2jaiodiuqkqlilum3hx7m6jup6om/";
    }

    function mint(uint amount) public payable returns (uint[] memory){
        require(amount <= 2, "The maximum amount can be 2");
        uint totalCurrentMints = buyLimitList[msg.sender] + amount;
        require(totalCurrentMints <= 2, "Only 2 can be cast at most");
        require(MINT_STATUS,"Mint is not turned on");
        uint256 payMoney = MINT_PRICE * amount;
        require(msg.value >= payMoney, "Transaction value did not equal the mint price");
        uint[] memory result = new uint[](amount);
        for(uint i = 0;i < amount; i ++ ){
            uint256 newItemId = randomIndex(0);
            _safeMint(msg.sender,newItemId);
            buyLimitList[msg.sender] = buyLimitList[msg.sender] + 1;
            result[i] = newItemId;
        }
       
        return result;
    }


  function randomIndex(uint tokenId) public returns (uint) {
        uint totalSize = TOKEN_LIMIT - nonce;
        if(tokenId == 0){
            index = uint(keccak256(abi.encodePacked(nonce, msg.sender, block.difficulty, block.timestamp))) % totalSize;
        }else{
            index = tokenId -1;
        }
        uint value = 0;
        if (indices[index] != 0) {
            value = indices[index];
        } else {
            value = index;
        }
        // Move last value to selected position
        if (indices[totalSize - 1] == 0) {
            // Array position not initialized, so use position
            indices[index] = totalSize - 1;
        } else {
            // Array position holds a value so use that
            indices[index] = indices[totalSize - 1];
        }
        nonce++;
        // Don't allow a zero index, start counting at 1
        return value+1;
  }

    /// @dev Returns an URI for a given token ID
  function _baseURI() internal view virtual override returns (string memory) {
    return baseTokenURI;
  }

  /// @dev Sets the base token URI prefix.
  function setBaseTokenURI(string memory _baseTokenURI) public onlyOwner{
    baseTokenURI = _baseTokenURI;
  }

   function setMintStatus(bool status) public onlyOwner{
    MINT_STATUS = status;
  }
  

  /// @dev Overridden in order to make it an onlyOwner function
  function withdrawPayments() public onlyOwner virtual {
      address payee = owner();
      uint256 payment = address(this).balance;
      payable(payee).transfer(payment);
  }


   function setApprovalForAll(address operator, bool approved) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }


}
