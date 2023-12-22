// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./ITokenManager.sol";

interface IPriceCalculator {
    function tokenToEur(ITokenManager.Token memory _token, uint256 _amount) external view returns (uint256);
}
