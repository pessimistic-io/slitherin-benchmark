// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import { FeeType } from "./Types.sol";

interface IFeeModule {
    /* ========= EVENTS ========= */

    event ProtocolFeeVaultUpdated();

    event ProtocolFeeUpdated();

    event ProjectAdded(uint256 indexed id);

    event ProjectStatusDisabled(uint256 indexed id);

    event ProjectFeeUpdated(uint256 indexed id);

    event ProjectFeeVaultUpdated(uint256 indexed id);

    /* ========= RESTRICTED ========= */

    function updateProtocolFee(FeeType[] calldata feeTypes_, uint256[] calldata fees_) external;

    function updateProtocolFeeVault(address newProtocolFeeVault_) external;

    function addProject(uint256[3] calldata fees_, address feeVault_) external;

    function disableProject(uint256 projectId_) external;

    function updateProjectFee(
        uint256 projectId_,
        FeeType[] memory feeTypes_,
        uint256[] memory fees_
    ) external;

    function updateProjectFeeVault(uint256 projectId_, address feeVault_) external;
}

