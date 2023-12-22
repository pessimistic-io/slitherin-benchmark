// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./EnumerableSet.sol";
import "./Ownable.sol";
import "./IFoxifyBlacklist.sol";

contract FoxifyBlacklist is Ownable, IFoxifyBlacklist {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _blacklist;

    function blacklist(uint256 index) external view returns (address) {
        return _blacklist.at(index);
    }

    function blacklistCount() external view returns (uint256) {
        return _blacklist.length();
    }

    function blacklistContains(address wallet) external view returns (bool) {
        return _blacklist.contains(wallet);
    }

    function blacklistList(uint256 offset, uint256 limit) external view returns (address[] memory output) {
        uint256 blacklistLength = _blacklist.length();
        uint256 to = offset + limit;
        if (blacklistLength < to) to = blacklistLength;
        output = new address[](to - offset);
        for (uint256 i = offset; i < to; i++) output[i - offset] = _blacklist.at(blacklistLength - i - 1);
    }

    function blacklistWallets(address[] memory wallets) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < wallets.length; i++) {
            _blacklist.add(wallets[i]);
        }
        emit Blacklisted(wallets);
        return true;
    }

    function unblacklistWallets(address[] memory wallets) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < wallets.length; i++) {
            _blacklist.remove(wallets[i]);
        }
        emit Unblacklisted(wallets);
        return true;
    }
}

