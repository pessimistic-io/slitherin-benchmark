// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

struct TokenAmount {
    address token;
    uint256 amount;
}

library TokenAmountLib {
    function add(
        TokenAmount[] memory list,
        address token,
        uint256 amount
    ) internal pure returns (TokenAmount[] memory newList) {
        if (amount == 0) return list;

        uint256 newTokenIndex = list.length;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].token == token) {
                newTokenIndex = i;
                break;
            }
        }

        newList = new TokenAmount[](list.length + (newTokenIndex == list.length ? 1 : 0));
        for (uint256 i = 0; i < list.length; i++) {
            newList[i] = list[i];
        }
        newList[newTokenIndex] = TokenAmount(
            token,
            (newTokenIndex == list.length ? 0 : list[newTokenIndex].amount) + amount
        );
    }

    function add(
        TokenAmount[] memory list,
        address[] memory tokens,
        uint256[] memory amounts
    ) internal pure returns (TokenAmount[] memory newList) {
        newList = list;
        require(tokens.length == amounts.length, "TokenAmountLib: length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            newList = add(newList, tokens[i], amounts[i]);
        }
        return newList;
    }
}

