// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IReferralStorage} from "./IReferralStorage.sol";
import {EnumerableSet} from "./EnumerableSet.sol";

contract ReferralStorage is IReferralStorage {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    mapping(bytes32 => address) public override codeOwners;
    mapping(address => bytes32) public referralCodes;
    mapping(address => EnumerableSet.Bytes32Set) private _ownedCodes;

    event SetReferralCode(address account, bytes32 code);
    event RegisterCode(address account, bytes32 code);
    event SetCodeOwner(address account, address newAccount, bytes32 code);

    error InvalidCode(bytes32 code);
    error CodeAlreadyExists();
    error NotCodeOwner();

    function setReferralCodeByUser(bytes32 _code) override external {
        _setReferralCode(msg.sender, _code);
    }

    function registerCode(bytes32 _code) external {
        if (_code == bytes32(0)) revert InvalidCode(_code);
        if (codeOwners[_code] != address(0)) revert CodeAlreadyExists();

        codeOwners[_code] = msg.sender;
        _ownedCodes[msg.sender].add(_code);
        emit RegisterCode(msg.sender, _code);
    }

    function setCodeOwner(bytes32 _code, address _newAccount) external {
        if (_code == bytes32(0)) revert InvalidCode(_code);

        address account = codeOwners[_code];
        if (msg.sender != account) revert NotCodeOwner();

        codeOwners[_code] = _newAccount;
        _ownedCodes[msg.sender].remove(_code);
        _ownedCodes[_newAccount].add(_code);
        emit SetCodeOwner(msg.sender, _newAccount, _code);
    }

    function getOwnedCodes(address _account) override external view returns (bytes32[] memory) {
        return _ownedCodes[_account].values();
    }

    function getReferralInfo(address _account) override external view returns (bytes32, address) {
        bytes32 code = referralCodes[_account];
        address referrer;
        if (code != bytes32(0)) {
            referrer = codeOwners[code];
        }
        return (code, referrer);
    }

    function _setReferralCode(address _account, bytes32 _code) private {
        referralCodes[_account] = _code;
        emit SetReferralCode(_account, _code);
    }
}

