// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Ownable } from "./Ownable.sol";
import { IReferralStorage } from "./IReferralStorage.sol";

contract ReferralStorage is Ownable, IReferralStorage {
    mapping(bytes32 => address) public codeOwners;
    mapping(address => bytes32) public referralCodes;
    mapping(address => uint256) public codeCounts;
    mapping(address => mapping(uint256 => bytes32)) public numberToCodes;
    mapping(address => bool) public isHandler;

    event RegisterCode(address _recipient, bytes32 _code);
    event SetReferralCode(address _recipient, bytes32 _code);
    event SetHandler(address _handler, bool _isActive);

    modifier onlyHandler() {
        require(isHandler[msg.sender], "ReferralStorage: Forbidden");
        _;
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
        emit SetHandler(_handler, _isActive);
    }

    function registerCode(bytes32 _code) external {
        require(_code != bytes32(0), "ReferralStorage: Invalid _code");
        require(codeOwners[_code] == address(0), "ReferralStorage: Code already exists");

        codeCounts[msg.sender]++;
        codeOwners[_code] = msg.sender;
        numberToCodes[msg.sender][codeCounts[msg.sender]] = _code;

        emit RegisterCode(msg.sender, _code);
    }

    function setReferralCode(address _recipient, bytes32 _code) external override onlyHandler {
        _setReferralCode(_recipient, _code);
    }

    function setReferralCodeByUser(bytes32 _code) external {
        _setReferralCode(msg.sender, _code);
    }

    function _setReferralCode(address _recipient, bytes32 _code) private {
        referralCodes[_recipient] = _code;

        emit SetReferralCode(_recipient, _code);
    }

    function getReferralInfo(address _recipient) external view returns (bytes32 code, address referrer) {
        code = referralCodes[_recipient];

        if (code != bytes32(0)) {
            referrer = codeOwners[code];
        }
    }
}

