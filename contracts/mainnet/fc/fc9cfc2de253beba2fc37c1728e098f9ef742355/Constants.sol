// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract Constants {
    //seaport
    address public constant SEAPORT =
        0x00000000006c3852cbEf3e08E8dF289169EdE581;
    uint256 public constant SEAPORT_MARKET_ID = 0;

    //looksrare
    address public constant LOOKSRARE =
        0x59728544B08AB483533076417FbBB2fD0B17CE3a;
    uint256 public constant LOOKSRARE_MARKET_ID = 1;
    //x2y2
    address public constant X2Y2 = 0x74312363e45DCaBA76c59ec49a7Aa8A65a67EeD3; //单个购买时的market合约
    // address public constant X2Y2_BATCH =
    //     0x56Dd5bbEDE9BFDB10a2845c4D70d4a2950163044; // 批量购买时的market合约--参考用
    uint256 public constant X2Y2_MARKET_ID = 2;
    //cryptopunk
    address public constant CRYPTOPUNK =
        0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
    uint256 public constant CRYPTOPUNK_MARKET_ID = 3;
    //mooncat
    address public constant MOONCAT =
        0x60cd862c9C687A9dE49aecdC3A99b74A4fc54aB6;
    uint256 public constant MOONCAT_MARTKET_ID = 4;

    struct ERC20Detail {
        address tokenAddr;
        uint256 amount;
    }

    struct ERC721Detail {
        address tokenAddr;
        uint256 id;
    }

    struct ERC1155Detail {
        address tokenAddr;
        uint256 id;
        uint256 amount;
    }
    struct OrderItem {
        ItemType itemType;
        address tokenAddr;
        uint256 id;
        uint256 amount;
    }
    enum ItemType {
        INVALID,
        NATIVE,
        ERC20,
        ERC721,
        ERC1155
    }
    struct TradeInput {
        uint256 value; // 此次调用x2y2\looksrare\..需传递的主网币数量
        bytes inputData; //此次调用的input data
        OrderItem[] tokens; // 本次调用要购买的NFT信息
    }
}

