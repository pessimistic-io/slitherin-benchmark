// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IWhitelistRegistry {
    function addToWhitelist(address _whitelistee) external;

    function removeFromWhitelist(address _whitelistee) external;

    function bulkAddToWhitelist(address[] calldata _whitelistees) external;

    function bulkremoveFromWhitelist(address[] calldata _whitelistees) external;

    function checkWhitelistStatus(address _whitelistee)
        external
        view
        returns (bool);
}

