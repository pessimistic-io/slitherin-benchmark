//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IUserManager.sol";

interface Userable is IUserManager {
    struct BaseApr {
        uint256 apr;
        uint256 priceMin;
        uint256 priceMax;
    }

    function balanceOfTokenID(uint256 tokenID) external returns (uint256);

    function credit(uint256 tokenID, uint256 amount) external;

    function debit(uint256 tokenID, uint256 amount) external;

    function updateUserGame(
        uint256 tokenID,
        uint256 gameID
    ) external;
}

