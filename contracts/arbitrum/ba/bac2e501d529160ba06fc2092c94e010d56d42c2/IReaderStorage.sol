//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IReaderStorage {
    struct Perp {
        address vault;
        address marketRegistry;
        address clearingHouse;
    }

    struct Gmx {
        address vault;
        address router;
        address positionRouter;
        address orderBook;
        address reader;
    }
}

