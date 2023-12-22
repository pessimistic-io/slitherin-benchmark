// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

library Storage {
    
    struct NETWORK{
        bool valid;
        uint8 decimals;
    }

    struct TKN{
        uint256 origin_network;
        string origin_hash;
        uint8 origin_decimals;
    }
}

library Bridge {

    struct TICKET{
        address dst_address;
        uint256 dst_network;
        uint256 amount;
        string src_hash;
        string src_address;
        uint256 src_network;
        string origin_hash;
        uint256 origin_network;
        uint256 nonce;
        string name;
        string symbol;
        uint8 origin_decimals;
    }
}
