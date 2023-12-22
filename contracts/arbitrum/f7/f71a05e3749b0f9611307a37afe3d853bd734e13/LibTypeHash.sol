// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

library LibTypeHash {

    //keccak256(abi.encodePacked(
    //    "BulkOrder(",
    //        "NFTBuyOrder[2] tree"
    //    ")",
    //    "Fee(",
    //        "address recipient,",
    //        "uint256 amount,",
    //        "bytes feeData",
    //    ")",
    //    "NFTBuyOrder(",
    //        "address maker,",
    //        "address taker,",
    //        "uint256 expiry,",
    //        "uint256 nonce,",
    //        "address erc20Token,",
    //        "uint256 erc20TokenAmount,",
    //        "Fee[] fees,",
    //        "address nft,",
    //        "uint256 nftId,",
    //        "Property[] nftProperties,",
    //        "uint256 hashNonce",
    //    ")",
    //    "Property(",
    //        "address propertyValidator,",
    //        "bytes propertyData",
    //    ")"
    //));
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H1 = 0xb32e6b07ca7f956efdb96d28fed6462c6d478d4f66692a6773741b404ff85f74;

    //keccak256(abi.encodePacked(
    //    "BulkOrder(",
    //        "NFTBuyOrder[2][2] tree"
    //    ")",
    //    "Fee(",
    //        "address recipient,",
    //        "uint256 amount,",
    //        "bytes feeData",
    //    ")",
    //    "NFTBuyOrder(",
    //        "address maker,",
    //        "address taker,",
    //        "uint256 expiry,",
    //        "uint256 nonce,",
    //        "address erc20Token,",
    //        "uint256 erc20TokenAmount,",
    //        "Fee[] fees,",
    //        "address nft,",
    //        "uint256 nftId,",
    //        "Property[] nftProperties,",
    //        "uint256 hashNonce",
    //    ")",
    //    "Property(",
    //        "address propertyValidator,",
    //        "bytes propertyData",
    //    ")"
    //));
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H2 = 0x9f75ca91e1048cc22959b86e890a322468993b0042056da157f2b412c6448a67;

    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H3 = 0x0b9237358bc0780db84404e8ac4354d9f65ad89d2f69ee36feef85323cc50e56;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H4 = 0x1d7449e626c1883d0a685a1eda892c4ebbec2fee5314d96df22ec6075af7e6da;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H5 = 0x3bd53d6120daeed6dfbe380dea0375dc8998073981bdb5b77d06c322e9f2d647;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H6 = 0x5ee31cf4765667f4d0fb661820bbfe26e1583a3035f58a2fa02f1bba4e6fbd6c;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H7 = 0xb608f4e4a9cd3cfd2c8cfccdad26888534996b0ae42be788464d9f617736ca9a;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H8 = 0x46b6148f58b19871db49b6f83360c40fa5c1245310a5a68a58ebd575aa83ed13;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H9 = 0xa8a9bda09e5a02cacb2dead999ab5f3a42c31378575a118d3610c7fcd0f5f589;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H10 = 0x104d0c688b877378c48931b8ab8d4cd40b91a284864372a291f5f0781080320a;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H11 = 0x566bb180c8b6c356458ac8ac2b1f94a344f13ad2cab2a0368fb5e0f63995271c;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H12 = 0xea284288a7b9efcb7bfa8960c9fee47e83a928c769634a8ccd84de1f04ab5cca;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H13 = 0x07f743265e8e61a1b890adf806926567cc011ebdfa491d5accc08a0c353056f2;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H14 = 0x3cb41bc57327bfc80e77688d75fd37ae8d661f2d347e724e8f5e417022f9796f;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H15 = 0xc79245b07759ae6288019cddb41b3cf90ca8ee2f5c8339d99b111efc6544a867;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H16 = 0xacd68817a805cfc3b06f56b3bbb5fcbdf8e945abd065de4c81c580533f7a600a;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H17 = 0xd57701e882860956e3f7872db1e179d6b8fc8e13a5398bb6af893a5e42e77839;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H18 = 0x2f3ed58d4e1d0a4c76f70032ee82f302118bfbadf3b0c39721868115a2bb020b;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H19 = 0x185fae4db124d03654cdc4beefd2f59ae93e9cc2f04eda3d86eefc6ad69fb653;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H20 = 0x8284117e9b7752fa6a09985a8ad343a0f36e4399dc23841b852b06f61c494944;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H21 = 0x4645af7b9f125b178e9090156cc187c311456985f773afde066dad652981a8db;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H22 = 0x15c4e80ebf08449122359b63924db2ae4aefad40b75bef4b6a4325cf2f72ce9c;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H23 = 0xa18f3d5fd85a19d6b8db5ebd2d5e31db3fb730b2d30a046b473c0137a2fc8056;
    bytes32 private constant _BULK_ERC721_BUY_ORDER_TYPE_HASH_H24 = 0x637175f391c9fa3e7d2456fc5f4d663cb628d453586604ba35d7a0f2d89f958b;

    //keccak256(abi.encodePacked(
    //    "BulkOrder(",
    //        "ERC1155BuyOrder[2] tree",
    //    ")",
    //    "ERC1155BuyOrder(",
    //        "address maker,",
    //        "address taker,",
    //        "uint256 expiry,",
    //        "uint256 nonce,",
    //        "address erc20Token,",
    //        "uint256 erc20TokenAmount,",
    //        "Fee[] fees,",
    //        "address erc1155Token,",
    //        "uint256 erc1155TokenId,",
    //        "Property[] erc1155TokenProperties,",
    //        "uint128 erc1155TokenAmount,",
    //        "uint256 hashNonce",
    //    ")",
    //    "Fee(",
    //        "address recipient,",
    //        "uint256 amount,",
    //        "bytes feeData",
    //    ")",
    //    "Property(",
    //        "address propertyValidator,",
    //        "bytes propertyData",
    //    ")"
    //));
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H1 = 0x06ebd50d9a0478e933167ddd59b33aad59b9601007b8ab0644d5317274fa477c;

    //keccak256(abi.encodePacked(
    //    "BulkOrder(",
    //        "ERC1155BuyOrder[2][2] tree",
    //    ")",
    //    "ERC1155BuyOrder(",
    //        "address maker,",
    //        "address taker,",
    //        "uint256 expiry,",
    //        "uint256 nonce,",
    //        "address erc20Token,",
    //        "uint256 erc20TokenAmount,",
    //        "Fee[] fees,",
    //        "address erc1155Token,",
    //        "uint256 erc1155TokenId,",
    //        "Property[] erc1155TokenProperties,",
    //        "uint128 erc1155TokenAmount,",
    //        "uint256 hashNonce",
    //    ")",
    //    "Fee(",
    //        "address recipient,",
    //        "uint256 amount,",
    //        "bytes feeData",
    //    ")",
    //    "Property(",
    //        "address propertyValidator,",
    //        "bytes propertyData",
    //    ")"
    //));
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H2 = 0x4332f3188d5bb5242a3a339824172cfb862da9a98bdf15d2f3848f8783766dd5;

    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H3 = 0x87b864a12bd96bac99659ad9646f04c0f6c39acb3483c86a40a47827ef897335;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H4 = 0x42515109fd2a179614d2a474ec133d28e5bce67542bbef6a1b1fb62b25da339f;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H5 = 0xaa709ab5849d659b0353cb57d3c90683b42e2b8e62557bb8e223575b36a29193;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H6 = 0x93111c998b9ec794d3f7f9f78520127bdb0c6bda5828c2d7635acd22950e6a37;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H7 = 0xb3ca47945f9f0e15d66c40ea7e058f536b2786ad1dd0092e38b818c9c103ddf4;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H8 = 0x56dacd6541283724269fe4e1e594041051c468721515df149e93087f9f08d366;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H9 = 0x00eb4936508848784f84148e6991b8871b33b7294b5244fba02750707efb3b59;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H10 = 0x1714ec693e1151b0d729959f2cea29a73169e92f732ea954aa1b34a268bc0a87;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H11 = 0x65114dd56a2f51a81c23d9e3a188eb19f23fbd857cf8b82b07628097cb996c0f;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H12 = 0x12ea41af8949c9b9a1ff2f736c9f66f9f73d951d3fcc82fbc259bcd209b44cc8;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H13 = 0x4f9a50789d3b21f7488444c8cd2127cd053f392bf178b58c30ec77626b771b2c;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H14 = 0xd123519b5ba947f405714106adf05c84cf33d1f4fabdf6b8b0d39bc019cbfdc3;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H15 = 0xbda87bfa1b02253d1a998f3573de8dcba18f231b599dc8d2274ad5704cb1d38c;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H16 = 0xcd80c0f13a214422a206fabdaa05d589907caba334846313f26a8d232877a5f4;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H17 = 0xb1a57f9ea04d4ce6d097926804b8a8093ae1a2f8f548cc514ae40770c871de7e;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H18 = 0x6d7c4ff60fce4c988ada572ff5447cfd4115329b5d98772281a5e8384e9d113d;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H19 = 0x5f36116fda20ab7b32eb8caf91980ccefa90ef7a3f0bbfe050288fb8d003e84d;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H20 = 0xfae6e9c50581dae3168b4d985e5d97e7e2c9230247637dc61b2259d889a0d383;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H21 = 0x6dcc44cb1bc3ba7c371b85bdedc36c93946f2b76443e1162f193c3f6f6921ba5;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H22 = 0x3175465e5d744b6896e381eda137c21e735b1d28df7df35b8c99b1d1313b2221;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H23 = 0xdbd25fdd09ccad35a5d6f9f4b983752a7db2bcc81d60b7a5042abb6a557b5ec0;
    bytes32 private constant _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H24 = 0x951ea5e5cd28bc4be27643958417c4d76f998d804c5dd114174e944d60ea7d80;

    function getBulkERC721BuyOrderTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height < 7) {
            if (height == 2) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H2;
            }
            if (height == 3) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H3;
            }
            if (height == 4) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H4;
            }
            if (height == 5) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H5;
            }
            if (height == 1) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H1;
            }
            if (height == 6) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H6;
            }
        }
        if (height < 13) {
            if (height == 7) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H7;
            }
            if (height == 8) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H8;
            }
            if (height == 9) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H9;
            }
            if (height == 10) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H10;
            }
            if (height == 11) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H11;
            }
            if (height == 12) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H12;
            }
        }

        if (height < 19) {
            if (height == 13) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H13;
            }
            if (height == 14) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H14;
            }
            if (height == 15) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H15;
            }
            if (height == 16) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H16;
            }
            if (height == 17) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H17;
            }
            if (height == 18) {
                return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H18;
            }
        }
        if (height == 19) {
            return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H19;
        }
        if (height == 20) {
            return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H20;
        }
        if (height == 21) {
            return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H21;
        }
        if (height == 22) {
            return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H22;
        }
        if (height == 23) {
            return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H23;
        }
        if (height == 24) {
            return _BULK_ERC721_BUY_ORDER_TYPE_HASH_H24;
        }
        revert("getBulkERC721BuyOrderTypeHash error");
    }

    function getBulkERC1155BuyOrderTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height < 7) {
            if (height == 2) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H2;
            }
            if (height == 3) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H3;
            }
            if (height == 4) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H4;
            }
            if (height == 5) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H5;
            }
            if (height == 1) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H1;
            }
            if (height == 6) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H6;
            }
        }
        if (height < 13) {
            if (height == 7) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H7;
            }
            if (height == 8) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H8;
            }
            if (height == 9) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H9;
            }
            if (height == 10) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H10;
            }
            if (height == 11) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H11;
            }
            if (height == 12) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H12;
            }
        }

        if (height < 19) {
            if (height == 13) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H13;
            }
            if (height == 14) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H14;
            }
            if (height == 15) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H15;
            }
            if (height == 16) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H16;
            }
            if (height == 17) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H17;
            }
            if (height == 18) {
                return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H18;
            }
        }
        if (height == 19) {
            return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H19;
        }
        if (height == 20) {
            return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H20;
        }
        if (height == 21) {
            return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H21;
        }
        if (height == 22) {
            return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H22;
        }
        if (height == 23) {
            return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H23;
        }
        if (height == 24) {
            return _BULK_ERC1155_BUY_ORDER_TYPE_HASH_H24;
        }
        revert("getBulkERC1155BuyOrderTypeHash error");
    }
}

