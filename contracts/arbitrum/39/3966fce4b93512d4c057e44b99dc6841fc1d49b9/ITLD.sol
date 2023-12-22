// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITLD {
    function setMaxSupply(uint256 _maxSupply) external;

    function adminSafeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external;

    function burn(uint256 _tokenId) external;

    function mint(address _to, uint256 _amount) external;
}

