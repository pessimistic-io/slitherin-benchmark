// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.10;

interface IOnwardIncentivesController {
    function handleAction(
        address _token,
        address _user,
        uint256 _balance,
        uint256 _totalSupply
    ) external;
}

