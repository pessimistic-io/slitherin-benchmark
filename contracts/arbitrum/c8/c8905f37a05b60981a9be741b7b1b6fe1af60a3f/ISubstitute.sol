// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface ISubstitute {
    event SetTreasury(address indexed newTreasury);
    event Claim(address indexed treasury, uint256 adminYield);

    error InvalidToken();
    error ValueTransferFailed();

    function treasury() external view returns (address);

    function underlyingToken() external view returns (address);

    function mint(uint256 amount, address to) external;

    function burn(uint256 amount, address to) external;

    function claim() external;

    function mintableAmount() external view returns (uint256);

    function burnableAmount() external view returns (uint256);

    function setTreasury(address newTreasury) external;

    function withdrawLostToken(address token, address recipient) external;
}

