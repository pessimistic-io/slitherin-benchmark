// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

interface ILibrary {

    function receiveTransfer(address _account, uint256 _amount, address _oldPool, bool _isFromVesting) external;

    function endRewards() external;

    function editCoinBooks(address _coinBook, bool _isCoinBook) external;

}
