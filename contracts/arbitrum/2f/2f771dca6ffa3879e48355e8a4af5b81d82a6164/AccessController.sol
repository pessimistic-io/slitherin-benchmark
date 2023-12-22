// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./access_AccessController.sol";

contract $AccessController is AccessController {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    constructor() {}

    function $MULTIPLY_FACTOR() external pure returns (uint128) {
        return MULTIPLY_FACTOR;
    }

    function $SIXTY_PERCENT() external pure returns (uint16) {
        return SIXTY_PERCENT;
    }

    function $_addOwner(address _newOwner) external {
        super._addOwner(_newOwner);
    }

    function $_addGuardian(address _newGuardian) external {
        super._addGuardian(_newGuardian);
    }

    function $_removeOwner(address _owner) external {
        super._removeOwner(_owner);
    }

    function $_removeGuardian(address _guardian) external {
        super._removeGuardian(_guardian);
    }

    function $_checkIfSigned(uint256 _proposalId) external view returns (bool ret0) {
        (ret0) = super._checkIfSigned(_proposalId);
    }

    function $_checkQuorumReached(uint256 _proposalId) external view returns (bool ret0) {
        (ret0) = super._checkQuorumReached(_proposalId);
    }

    receive() external payable {}
}

