// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721Holder.sol";
import "./ERC1155Holder.sol";
import "./IERC1155.sol";
import "./IERC721.sol";
import "./Ownable.sol";
import "./OwnableUpgradeable.sol";

import "./IPoints.sol";
import "./IRoleManager.sol";
import "./INFTStore.sol";
import "./Types.sol";
import "./GlobalNftLib.sol";
import "./IHuntNFTFactory.sol";

contract NFTStore is OwnableUpgradeable, ERC721Holder, ERC1155Holder, INFTStore {
    IHuntNFTFactory factory;
    IRoleManager roleManager;
    IPoints point;
    /// originChainId=>isErc1155=>nft=>tokenId=>price
    mapping(uint64 => mapping(bool => mapping(address => mapping(uint256 => uint256)))) public override getPrice;

    function initialize(IHuntNFTFactory _factory, IRoleManager _roleManager, IPoints _point) public initializer {
        __Ownable_init();

        factory = _factory;
        roleManager = _roleManager;
        point = _point;
    }

    function listNft(uint64 originChain, bool isErc1155, address addr, uint256 tokenId, uint64 price) public {
        require(roleManager.isStoreOperator(msg.sender), "ERR_ROLE");
        require(price > 0, "empty price");
        require(GlobalNftLib.isOwned(factory.getHuntBridge(), originChain, isErc1155, addr, tokenId), "NOT_DEPOSITED");
        getPrice[originChain][isErc1155][addr][tokenId] = price;
        emit NftListed(originChain, isErc1155, addr, tokenId, price);
    }

    function buyNftAndWithdraw(uint64 originChain, bool isErc1155, address addr, uint256 tokenId) public payable {
        buyNft(originChain, isErc1155, addr, tokenId, true);
    }

    function buyNft(uint64 originChain, bool isErc1155, address addr, uint256 tokenId, bool withdraw) public payable {
        uint256 price = getPrice[originChain][isErc1155][addr][tokenId];
        require(price > 0, "SOLD_OUT");
        point.consumePoint(msg.sender, uint64(price));
        delete getPrice[originChain][isErc1155][addr][tokenId];

        GlobalNftLib.transfer(factory.getHuntBridge(), originChain, isErc1155, addr, tokenId, msg.sender, withdraw);
        emit NftBought(originChain, isErc1155, addr, tokenId, uint64(price), msg.sender);
    }

    /// dao
    function setFactory(IHuntNFTFactory _factory) public onlyOwner {
        factory = _factory;
    }
}

