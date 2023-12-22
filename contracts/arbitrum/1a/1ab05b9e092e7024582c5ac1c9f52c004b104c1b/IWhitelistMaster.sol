// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

interface IWhitelistMaster {
    function addToWhitelist(address[] memory _addresses) external;

    function removeFromWhitelist(address[] memory _addresses) external;

    function isWhitelisted(address _address) external returns (bool);
}

