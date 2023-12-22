// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
pragma experimental ABIEncoderV2;

import "./AccountManager.sol";
import "./ISortedAccounts.sol";

import "./Initializable.sol";

/*  Helper contract for grabbing Account data for the front end. Not part of the core Unbound system. */
contract MultiAccountGetter is Initializable{
    struct CombinedAccountData {
        address owner;
        uint debt;
        uint coll;
    }

    AccountManager public accountManager;
    ISortedAccounts public sortedAccounts;

    function initialize(address _accountManager, address _sortedAccounts) public initializer {
        accountManager = AccountManager(_accountManager);
        sortedAccounts = ISortedAccounts(_sortedAccounts);
    }

    function getMultipleSortedAccounts(int _startIdx, uint _count)
        external view returns (CombinedAccountData[] memory _accounts)
    {
        uint startIdx;
        bool descend;

        if (_startIdx >= 0) {
            startIdx = uint(_startIdx);
            descend = true;
        } else {
            startIdx = uint(-(_startIdx + 1));
            descend = false;
        }

        uint sortedAccountsSize = sortedAccounts.getSize();

        if (startIdx >= sortedAccountsSize) {
            _accounts = new CombinedAccountData[](0);
        } else {
            uint maxCount = sortedAccountsSize - startIdx;

            if (_count > maxCount) {
                _count = maxCount;
            }

            if (descend) {
                _accounts = _getMultipleSortedAccountsFromHead(startIdx, _count);
            } else {
                _accounts = _getMultipleSortedAccountsFromTail(startIdx, _count);
            }
        }
    }

    function _getMultipleSortedAccountsFromHead(uint _startIdx, uint _count)
        internal view returns (CombinedAccountData[] memory _accounts)
    {
        address currentAccountowner = sortedAccounts.getFirst();

        for (uint idx = 0; idx < _startIdx; ++idx) {
            currentAccountowner = sortedAccounts.getNext(currentAccountowner);
        }

        _accounts = new CombinedAccountData[](_count);

        for (uint idx = 0; idx < _count; ++idx) {
            _accounts[idx].owner = currentAccountowner;
            (
                _accounts[idx].debt,
                _accounts[idx].coll,
                /* status */,
                /* arrayIndex */
            ) = accountManager.Accounts(currentAccountowner);

            currentAccountowner = sortedAccounts.getNext(currentAccountowner);
        }
    }

    function _getMultipleSortedAccountsFromTail(uint _startIdx, uint _count)
        internal view returns (CombinedAccountData[] memory _accounts)
    {
        address currentAccountowner = sortedAccounts.getLast();

        for (uint idx = 0; idx < _startIdx; ++idx) {
            currentAccountowner = sortedAccounts.getPrev(currentAccountowner);
        }

        _accounts = new CombinedAccountData[](_count);

        for (uint idx = 0; idx < _count; ++idx) {
            _accounts[idx].owner = currentAccountowner;
            (
                _accounts[idx].debt,
                _accounts[idx].coll,
                /* status */,
                /* arrayIndex */
            ) = accountManager.Accounts(currentAccountowner);

            currentAccountowner = sortedAccounts.getPrev(currentAccountowner);
        }
    }
}
