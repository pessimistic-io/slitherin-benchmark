// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./AccessControl.sol";

contract ExcessClaimableUser is AccessControl {

/** Roles **/
    bytes32 public constant Claimer = keccak256("Claimer");

    bytes32 public constant Consumer = keccak256("Consumer");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

/** Excess Claimable **/
    mapping (address => uint256) public ExcessClaimable;

    function getExcess(address sender) external view returns (uint256) {
        return ExcessClaimable[sender];
    }

    function setExcess(address sender, uint256 amount) external onlyRole(Claimer) {
        ExcessClaimable[sender] = amount;
    }

    function consumeExcess(address sender, uint256 amount) external onlyRole(Consumer) {
        require(ExcessClaimable[sender] >= amount, "Excess Claimable User: Not enough balance.");
        ExcessClaimable[sender] -= amount;
    }
}
