// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./layer2_ONFT721.sol";

contract OmniNFT721 is ONFT721 {
    string private _baseUri;
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _minGasToTransfer,
        address _lzEndpoint
    ) ONFT721(_name, _symbol, _minGasToTransfer, _lzEndpoint) {
    }

    function setBaseURI(string memory uri) external onlyOwner {
        _baseUri = uri;
    }

    function _baseURI() internal override view returns (string memory) {
        return _baseUri;
    }
}

