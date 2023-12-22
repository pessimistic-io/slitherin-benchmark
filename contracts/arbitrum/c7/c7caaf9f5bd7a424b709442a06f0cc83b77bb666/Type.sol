pragma solidity ^0.8.9;

library Type {
    enum PostPrice {
        FixedPrice,
        FloorPrice
    }

    enum TypeFee {
        Owner,
        Protocol,
        Holder
    }

    enum PostStatus {
        Open,
        Hide,
        Delete
    }

    uint256 internal constant BASIC_POINT_FEE = 10_000;

    address internal constant NATIVE_ADDRESS =
        0x0000000000000000000000000000000000000001;
}

