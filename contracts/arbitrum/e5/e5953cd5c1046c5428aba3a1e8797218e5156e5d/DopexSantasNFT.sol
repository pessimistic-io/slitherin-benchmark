// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.17;

import {BaseNFT} from "./BaseNFT.sol";

contract DopexSantasNFT is BaseNFT {
    constructor(bytes32 _merkleRoot)
        BaseNFT('Dopex Santas NFT', 'DPX_SANTAS_NFT', _merkleRoot)
    {}
}

