// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.7.6;

import {BaseNFT} from "./BaseNFT.sol";

contract DopexBridgoorNFT is BaseNFT {
    constructor(string memory _baseTokenURI, bytes32 _merkleRoot)
        BaseNFT(
            'Dopex Bridgoor NFT',
            'DPX_BRIDGOOR_NFT',
            _baseTokenURI,
            _merkleRoot
        )
    {}
}

