// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

interface IALP {
    function payWin(address _account, uint256 _game, bytes32 _requestId, uint256 _amount) external;
    function receiveLoss(address _account, uint256 _game, bytes32 _requestId, uint256 _amount) external;
}

