// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.7;

interface IWhitelist {
    function isWhitelisted(
        address _account,
        uint256 _currentAssets,
        uint256 _amount,
        bytes32[] calldata _merkleproof
    ) external returns (bool);
}

