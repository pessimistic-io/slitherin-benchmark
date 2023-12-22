// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.7.6;

import {BaseNFT} from "./BaseNFT.sol";

contract DopexHalloweenNFT is BaseNFT {
    constructor(string memory _baseTokenURI, bytes32 _merkleRoot)
        BaseNFT(
            'Dopex Halloween NFT',
            'DPX_HALLOWEEN_NFT',
            _baseTokenURI,
            _merkleRoot
        )
    {}
}

