// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ICue {
    error CueTypeNotSupported();
    error ExceedMaxSupply();

    event TokenBaseURIUpdated(string uri);
    event CueMinted(address user, uint256 tokenId, uint256 cueType);

    function mint(address wallet, uint256 cueType) external returns (uint256);
}

