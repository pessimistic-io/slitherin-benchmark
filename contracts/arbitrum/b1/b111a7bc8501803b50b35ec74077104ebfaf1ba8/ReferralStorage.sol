// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./SafeMath.sol";
import {Ownable} from "./Ownable.sol";
import "./IReferralStorage.sol";


contract ReferralStorage is Ownable, IReferralStorage {
    using SafeMath for uint256;

    uint256 public commission = 300; // 3%
    mapping (bytes32 => address) public override codeOwners;
    mapping (address => bytes32) public createdCodes; // created code
    mapping (address => bytes32) public override userReferralCodes; // used codes

    function setUserReferralCode(address _account, bytes32 _code) external override onlyOwner {
        _setUserReferralCode(_account, _code);
    }

    function setUserReferralCodeByUser(bytes32 _code) external {
        _setUserReferralCode(msg.sender, _code);
    }

    function registerCode(bytes32 _code) external {
        require(_code != bytes32(0), "ReferralStorage: invalid _code");
        require(codeOwners[_code] == address(0), "ReferralStorage: code already exists");
        require(createdCodes[msg.sender] == bytes32(0), "ReferralStorage: you already have a code");
        require(userReferralCodes[msg.sender] != bytes32(0) || msg.sender == owner(), "ReferralStorage: you must have been referred by someone else");
        codeOwners[_code] = msg.sender;
    }

    function setCodeOwner(bytes32 _code, address _newAccount) external {
        require(_code != bytes32(0), "ReferralStorage: invalid _code");

        address account = codeOwners[_code];
        require(msg.sender == account, "ReferralStorage: forbidden");

        codeOwners[_code] = _newAccount;
    }

    function setCodeOwnerAdmin(bytes32 _code, address _newAccount) external override onlyOwner {
        require(_code != bytes32(0), "ReferralStorage: invalid _code");
        codeOwners[_code] = _newAccount;
    }

    function setCommission(uint256 _commission) external override onlyOwner {
        commission = _commission;
    }

    function getUserReferralInfo(address _account) external override view returns (bytes32, address) {
        bytes32 code = userReferralCodes[_account];
        address referrer;
        if (code != bytes32(0)) {
            referrer = codeOwners[code];
        }
        return (code, referrer);
    }

    function getReferrer(address _account) external override view returns (address) {
        bytes32 code = userReferralCodes[_account];
        if (code != bytes32(0)) {
            return codeOwners[code];
        }
        return address(0);
    }

    function _setUserReferralCode(address _account, bytes32 _code) private {
        userReferralCodes[_account] = _code;
    }
}
