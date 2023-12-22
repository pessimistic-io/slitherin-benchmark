
// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;

pragma solidity ^0.7.1;

import {DarwinSBT,Proxy, ERC721, ReentrancyGuarded, Ownable, Strings, Address, SafeMath, Context} from "./Darwin721.sol";
import {DarwinStore} from "./DarwinStore.sol";
import {Armory} from "./Armory.sol";
import {Character} from "./Character.sol";
import {Darwin1155,IERC1155,IERC1155Receiver} from "./Darwin1155.sol";
import {IERC20} from "./IERC20.sol";
import {ArrayUtils} from "./ArrayUtils.sol";

contract DarwinStoreProxy is  Proxy, DarwinStore{
    constructor() {
        
    }
    
    function upgradeTo(address impl) public onlyOwner {
        require(_implementation != impl);
        _implementation = impl;
    }
    
    /**
    * @return The Address of the implementation.
    */
    function implementation() public override virtual view returns (address){
        return _implementation;
    }
    
    
    /**
   * @dev Fallback function.
   * Implemented entirely in `_fallback`.
   */
  fallback () payable external {
    _fallback();
  }

  /**
   * @dev Receive function.
   * Implemented entirely in `_fallback`.
   */
  receive () payable external {
    _fallback();
  }
}


contract Darwin is  DarwinStore{

    using SafeMath for uint256;

    event CharacterMinted(address indexed player, uint256 indexed tokenId);

    event ClaimMine(address indexed player, uint256 indexed orderId);

    event Stack721(address indexed from, uint256 tokenId);

    event Withdrawal721(address indexed from, uint256 tokenId);

    event Stack1155(address indexed from, uint256[] ids, uint256[] values);

    event Withdrawal1155(address indexed from, uint256 indexed orderId, uint256[] ids, uint256[] values);
    
    constructor() {
        
    }
    
    function version() public pure returns (uint){
        return 1;
    }

    function orderIdExist(uint256 orderId) public view  returns (bool) {
        return _orderIdMap[orderId];
    }

    function isLootId(uint id) public pure returns(bool){
        return id == 9;
    }

    function isResourceId(uint id) public pure returns(bool){
        uint[5] memory nft1155Ids = [uint(100303),uint(100304),uint(100305),uint(100306),uint(100045)];
        for(uint i=0; i<nft1155Ids.length; ++i){
            if(id == nft1155Ids[i]){
                return true;
            }
        }
        return false;
    }

    function mint721(uint256 orderId, uint256 tokenId, uint32 tokenTag, uint[] memory ids, uint[] memory amounts, uint8 v, bytes32 r, bytes32 s) public payable reentrancyGuard{
        require(contractIsOpen, "Contract must active");
        
        require(verifyOrder(orderId, tokenId, tokenTag, ids, amounts, v, r, s),"verify Order error");

        require(withdrawalPrice() == msg.value, "withdrawal price unmatch");

        Armory(armoryNFT())._mintByAdmin(tokenId, tokenTag, msg.sender);
    }

    function mintMine(uint256 orderId, uint256 markTag, uint32 actionTag, uint[] memory ids, uint[] memory amounts, uint8 v, bytes32 r, bytes32 s) public reentrancyGuard {
        require(contractIsOpen, "Contract must active");
        
        require(verifyOrder(orderId, markTag, actionTag, ids, amounts, v, r, s),"verify Order error");

        for(uint i=0; i<ids.length; ++i){
            if(ids[i] == 0){
                continue;
            }
            require(isResourceId(ids[i]), "can't claim other nft id");
        }

        Darwin1155(_NFT1155).claim(msg.sender, ids, amounts, "claim mine");

        emit ClaimMine(msg.sender, orderId);
    }


    function mintCharacter(uint256 orderId, uint256 tokenId, uint32 tag, uint[] memory ids, uint[] memory amounts, uint8 v, bytes32 r, bytes32 s) public payable reentrancyGuard{
        require(contractIsOpen, "Contract must active");

        require(characterPrice() == msg.value, "character price unmatch");

        require(verifyOrder(orderId, tokenId, tag, ids, amounts, v, r, s),"verify Order error");

        Character(characterNFT())._mintByAdmin(tokenId, 0, msg.sender);
        
        emit CharacterMinted(msg.sender, tokenId);
    }

    function characterPrice() public pure returns (uint256){
        //0.0125 ETH - target price
        //uint256 price = 12500000000000000;

        //--test price = 0.000125
        uint256 price = 125000000000000;
        return price;
    }

    function withdrawalPrice() public pure returns (uint256){
        //0.0003 ETH - target price
        //uint256 price = 300000000000000;

        //--test price = 0.00003
        uint256 price = 30000000000000;
        return price;
    }



    function stack721(uint256 tokenId) public reentrancyGuard{
        require(contractIsOpen, "Contract must active");

        require(Armory(armoryNFT()).ownerOf(tokenId) == msg.sender, "the nft not yours");

        require(_stackArmoryMap[tokenId] == address(0), "the token is stacking");

        Armory(armoryNFT()).transferFrom(msg.sender, address(this), tokenId);

        _stackArmoryMap[tokenId] = msg.sender;

        emit Stack721(msg.sender, tokenId);
    }

    function withdrawal721(uint256 orderId, uint256 tokenId, uint32 tokenTag, uint[] memory ids, uint[] memory amounts, uint8 v, bytes32 r, bytes32 s) payable public reentrancyGuard{
        require(contractIsOpen, "Contract must active");

        require(withdrawalPrice() == msg.value, "withdrawal price unmatch");

        require(verifyOrder(orderId, tokenId, tokenTag, ids, amounts, v, r, s),"verify Order error");

        require(_stackArmoryMap[tokenId] == msg.sender, "the nft is not yours");

        require(Armory(armoryNFT()).ownerOf(tokenId) == address(this), "the nft is not stacking");

        Armory(armoryNFT()).transferFrom(address(this), msg.sender, tokenId);

        delete _stackArmoryMap[tokenId];

        emit Withdrawal721(msg.sender, tokenId);
    }

    function stack1155(uint256[] memory ids, uint256[] memory amounts) public reentrancyGuard{
        require(contractIsOpen, "Contract must active");

        require(ids.length == amounts.length, "ids size must equal amounts size");

        for(uint256 i=0; i<ids.length; ++i){
            require(Darwin1155(_NFT1155).balanceOf(msg.sender, ids[i]) >= amounts[i], "resource not enought");
        }

        //function safeBatchTransferFrom(address from, address to, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data) external;

        Darwin1155(_NFT1155).safeBatchTransferFrom(msg.sender, address(this), ids, amounts, "stack to game");

        emit Stack1155(msg.sender, ids, amounts);
    }


    function onERC1155Received(address, address, uint256, uint256, bytes memory) pure external returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }
    

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) pure external returns (bytes4) {
        return bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
    }

    function sizeOf()
        internal
        pure
        returns (uint)
    {   
        //address   = 0x14
        //uint      = 0x20
        //uint8     = 1
        //uint256   = 0x100
        //return (0x100 * 3 + 0x20 * 8 + 0x14 * 1);
        return (0x100 * 3 + 0x20 * 8);
    }
     // 签名账户
    function signAddress() private pure returns(address){
        return address(0x34C533Bdd04d02a71d836463Aae0503854734eF1);
    }

    function hashOrder(Order memory order) internal pure returns(bytes32 hash) {
        uint size = sizeOf();
        bytes memory array = new bytes(size);
        uint index;
        assembly {
            index := add(array, 0x20)
        }

        index = ArrayUtils.unsafeWriteUint(index, order.orderId);

        index = ArrayUtils.unsafeWriteUint(index, order.tokenId);

        index = ArrayUtils.unsafeWriteUint(index, order.tokenTag);
        
        for(uint i = 0; i< 4; i++){
            index = ArrayUtils.unsafeWriteUint(index, order.consumeId[i]);
        }

        for(uint i = 0; i< 4; i++){
            index = ArrayUtils.unsafeWriteUint(index, order.consumeAmount[i]);
        }
        
        assembly {
            hash := keccak256(add(array, 0x20), size)
        }
        return hash;
    }

    function hashOrder_(uint256 orderId, uint256 tokenId, uint256 tokenTag, uint[] memory consumeIds, uint[] memory consumeAmounts) public pure returns (bytes32){
        return hashOrder(
            Order(orderId, tokenId, tokenTag, consumeIds, consumeAmounts)
        );
    }

     function hashToSign_(uint256 orderId, uint256 tokenId, uint256 tokenTag, uint[] memory consumeIds, uint[] memory consumeAmounts) public pure returns (bytes32){
        return hashToSign(
            Order(orderId, tokenId, tokenTag, consumeIds, consumeAmounts)
        );
    }
  
     function hashToSign(Order memory order)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hashOrder(order)));
    }

    
    function cancelOrder(uint256 orderId) public reentrancyGuard {
        require(!orderIdExist(orderId), "Order id check error");

        _orderIdMap[orderId] = true;
    }

    function verifyOrder(uint256 orderId, uint256 tokenId, uint256 tokenTag, uint[] memory consumeIds, uint[] memory consumeAmounts, uint8 v, bytes32 r, bytes32 s) internal returns(bool)  {            

        require(validateOrder_(orderId, tokenId, tokenTag, consumeIds, consumeAmounts, v, r, s), "Order validate error");

        _orderIdMap[orderId] = true;

        return true;
    }

    /**
     * @dev Validate a provided previously approved / signed order, hash, and signature.
     * @param hash Order hash (already calculated, passed to avoid recalculation)
     * @param order Order to validate
     * @param sig ECDSA signature
     */
    function validateOrder(bytes32 hash, Order memory order, Sig memory sig) 
        internal
        view
        returns (bool)
    {
        /* Order must have not been canceled or already filled. */
        if (orderIdExist(order.orderId)) {
            return false;
        }
        
        /* or (b) ECDSA-signed by maker. */
        if (ecrecover(hash, sig.v, sig.r, sig.s) == signAddress()) {
            return true;
        }

        return false;
    }

    
    /**
     * @dev Call validateOrder - Solidity ABI encoding limitation workaround, hopefully temporary.
     */
    function validateOrder_ (
        uint256 orderId, uint256 tokenId, uint256 tokenTag, uint[] memory consumeIds, uint[] memory consumeAmounts, uint8 v, bytes32 r, bytes32 s) 
        view public returns (bool)
    {
        Order memory order = Order(orderId, tokenId, tokenTag, consumeIds, consumeAmounts);
        return validateOrder(
          hashToSign(order),
          order,
          Sig(v, r, s)
        );
    }
}


