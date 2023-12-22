// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Term, IAgreementManager} from "./Term.sol";

/// @notice Agreement Term that places no constraints.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/Right.sol)
abstract contract Right is Term {
    function constraintStatus(IAgreementManager, uint256) public pure virtual override returns (uint256) {
        return 100 ether;
    }
}

