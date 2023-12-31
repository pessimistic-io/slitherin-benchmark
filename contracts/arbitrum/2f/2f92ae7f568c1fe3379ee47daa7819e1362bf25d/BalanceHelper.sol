// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.5;

import "./IERC20.sol";

contract BalanceHelper {
    struct TokenBalance {
        uint256 total;
        uint256 allowance;
    }

    function balancesOf(address _user, IERC20[] memory _tokens, address _tokenSpender) public view returns (uint256 ethBalance, TokenBalance[] memory tokensBalances) {
        // Eth balance
        ethBalance = _user.balance;

        // Tokens balance
        tokensBalances = new TokenBalance[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokensBalances[i] = TokenBalance(
                _tokens[i].balanceOf(_user),
                _tokens[i].allowance(_user, _tokenSpender)
            );
        }
    }
}

