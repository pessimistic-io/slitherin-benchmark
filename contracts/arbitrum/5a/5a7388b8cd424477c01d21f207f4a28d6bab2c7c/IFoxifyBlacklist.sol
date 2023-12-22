// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IFoxifyBlacklist {
    function blacklist(uint256 index) external view returns (address);
    function blacklistCount() external view returns (uint256);
    function blacklistContains(address wallet) external view returns (bool);
    function blacklistList(uint256 offset, uint256 limit) external view returns (address[] memory output);

    event Blacklisted(address[] wallets);
    event Unblacklisted(address[] wallets);
}

