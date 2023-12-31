// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.7;

import "./IDecapacitor.sol";
import "./RescueFundsLib.sol";
import "./AccessControlExtended.sol";
import {RESCUE_ROLE} from "./AccessRoles.sol";

contract SingleDecapacitor is IDecapacitor, AccessControlExtended {
    /**
     * @notice initialises the contract with owner address
     */
    constructor(address owner_) AccessControlExtended(owner_) {
        _grantRole(RESCUE_ROLE, owner_);
    }

    /// returns if the packed message is the part of a merkle tree or not
    /// @inheritdoc IDecapacitor
    function verifyMessageInclusion(
        bytes32 root_,
        bytes32 packedMessage_,
        bytes calldata
    ) external pure override returns (bool) {
        return root_ == packedMessage_;
    }

    function rescueFunds(
        address token_,
        address userAddress_,
        uint256 amount_
    ) external onlyRole(RESCUE_ROLE) {
        RescueFundsLib.rescueFunds(token_, userAddress_, amount_);
    }
}

