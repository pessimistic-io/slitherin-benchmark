// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./Address.sol";

contract BalanceReader {
    using SafeMath for uint256;

    address private constant ETH_ADDRESS = address(0);

    function getBalances(
        address _user,
        address[] memory _assetIds
    )
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory balances = new uint256[](_assetIds.length);

        for (uint256 i = 0; i < _assetIds.length; i++) {
            if (_assetIds[i] == ETH_ADDRESS) {
                balances[i] = _user.balance;
                continue;
            }
            if (!Address.isContract(_assetIds[i])) {
                continue;
            }

            IERC20 token = IERC20(_assetIds[i]);
            balances[i] = token.balanceOf(_user);
        }

        return balances;
    }
}

