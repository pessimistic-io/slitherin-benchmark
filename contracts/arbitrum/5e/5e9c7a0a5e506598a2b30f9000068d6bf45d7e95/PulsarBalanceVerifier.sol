// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

import "./SafeMath.sol";

interface BalanceChecker {
    function balances(
        address[] memory users,
        address[] memory tokens
    ) external view returns (uint[] memory);
}

contract PulsarBalanceVerifier {
    BalanceChecker internal balanceChecker;

    constructor(address _balanceCheckerAddr) {
        balanceChecker = BalanceChecker(_balanceCheckerAddr);
    }

    function isEveryTokenBalanceCorrect(
        address[] memory _tokens,
        uint256[] memory _tokenBalances,
        address _walletAddress
    ) public view {
        address[] memory _walletAddresses = new address[](1);
        _walletAddresses[0] = _walletAddress;
        uint256[] memory _verifiedTokenBalances = balanceChecker.balances(
            _walletAddresses,
            _tokens
        );
        require(
            _verifiedTokenBalances.length == _tokenBalances.length,
            "Invalid verified token balances length"
        );

        for (uint256 i = 0; i < _verifiedTokenBalances.length; i++) {
            uint256 lowerBound = SafeMath.mul(_tokenBalances[i], 95) / 100;
            uint256 upperBound = SafeMath.mul(_tokenBalances[i], 105) / 100;
            require(
                _verifiedTokenBalances[i] >= lowerBound &&
                    _verifiedTokenBalances[i] <= upperBound,
                "Invalid token balance"
            );
        }
    }
}

