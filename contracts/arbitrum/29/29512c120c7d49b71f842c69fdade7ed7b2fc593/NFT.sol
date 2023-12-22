// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./UniversalONFT721.sol";

contract ZeroSquareNFT is UniversalONFT721 {
    constructor(
        uint256 _minGasToStore,
        address _layerZeroEndpoint,
        uint _startMintId,
        uint _endMintId
    )
        UniversalONFT721(
            "ZeroSquareNFT",
            "ZRNFT",
            _minGasToStore,
            _layerZeroEndpoint,
            _startMintId,
            _endMintId
        )
    {}
}

