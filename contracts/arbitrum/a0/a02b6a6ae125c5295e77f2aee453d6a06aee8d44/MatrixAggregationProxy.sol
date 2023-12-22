// SPDX-License-Identifier: MIT
import "./IERC20.sol";
import "./MatrixVault.sol";

pragma solidity ^0.8.6;

contract MatrixAggregationProxy {
    function userBalances(address _userAddress, address[] memory _vaults) public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](_vaults.length);

        for(uint i = 0; i < _vaults.length; i++) {
            MatrixVault vault = MatrixVault(_vaults[i]);
            uint256 balanceOfUser = vault.balanceOf(_userAddress);
            balances[i] = balanceOfUser;
        }

        return balances;
    }

    function usersBalances(address[] memory _users, address[] memory _vaults) public view returns (uint256[][] memory) {
        uint256[][] memory balances = new uint256[][](_users.length);

        for(uint i = 0; i < _users.length; i++) {
            balances[i] = userBalances(_users[i], _vaults);
        }

        return balances;
    }
}
