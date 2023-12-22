// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./xRAM.sol";

contract XWhitelist {
    mapping(address => bool) operators;
    XRam public xRam;
    address public multisig;

    modifier onlyOperators() {
        require(
            operators[msg.sender] == true,
            "xWhitelist: Only operators can call this function"
        );
        _;
    }
    modifier onlyMultisig() {
        require(
            msg.sender == multisig,
            "xWhitelist: Only the multisig can call this function"
        );
        _;
    }

    constructor(address _multisig) {
        (multisig, operators[multisig]) = (_multisig, true);
    }

    function addWhitelist(address _user) external onlyOperators {
        xRam.addWhitelist(_user);
    }

    function removeWhitelist(address _user) external onlyOperators {
        xRam.removeWhitelist(_user);
    }

    function modifyWhitelist(
        address[] calldata _candidates,
        bool[] calldata _statuses
    ) external onlyOperators {
        xRam.adjustWhitelist(_candidates, _statuses);
    }

    function migrateEnneadWhitelist(
        address _enneadWhitelist
    ) external onlyMultisig {
        xRam.migrateEnneadWhitelist(_enneadWhitelist);
    }

    function addOperator(address _newOperator) external onlyMultisig {
        operators[_newOperator] = true;
    }

    function removeOperator(address _newOperator) external onlyMultisig {
        operators[_newOperator] = false;
    }

    function changeMultisig(address _newMultisig) external onlyMultisig {
        multisig = _newMultisig;
    }

    function setXRam(address _xRam) external onlyMultisig {
        xRam = XRam(_xRam);
    }

    function isOperator(address _operator) public view returns (bool) {
        return operators[_operator];
    }
}

