// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.4;

import "./AccessControl.sol";

contract PoolOIStorage is AccessControl {
    uint256 public totalPoolOI;
    bytes32 public constant UPDATOR_ROLE = keccak256("UPDATOR_ROLE");
    event UpdatePoolOI(bool isIncreased, uint256 interest);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function updatePoolOI(
        bool isIncreased,
        uint256 interest
    ) external onlyRole(UPDATOR_ROLE) {
        if (isIncreased) {
            totalPoolOI += interest;
        } else {
            require(totalPoolOI >= interest, "Insufficient pool OI");
            totalPoolOI -= interest;
        }
        emit UpdatePoolOI(isIncreased, interest);
    }
}

