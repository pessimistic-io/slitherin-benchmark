// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {StockPlan} from "./StockPlan.sol";
import {AnnotatingMulticall} from "./AnnotatingMulticall.sol";
import {IAgreementManager} from "./IAgreementManager.sol";
import {AuthorizedShareToken} from "./AuthorizedShareToken.sol";
import {Authority} from "./AuthBase.sol";

import {Bytes32AddressLib} from "./Bytes32AddressLib.sol";

/// @notice A factory for deploying Stock Plans.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/StockPlanFactory.sol)
/// @author Modified from Vaults (https://github.com/Rari-Capital/vaults/blob/main/src/VaultFactory.sol)
contract StockPlanFactory is AnnotatingMulticall {
    using Bytes32AddressLib for address;
    using Bytes32AddressLib for bytes32;

    /*///////////////////////////////////////////////////////////////
                           DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice A counter indicating how many Stock Plans have been deployed.
    /// @dev This is used to generate the Stock Plan ID.
    uint256 public planNumber;

    /// @dev When a new Stock Plan is deployed, it will retrieve the
    /// values stored here. This enables the Stock Plan to be deployed to
    /// an address that does not require constructor args to determine.
    AuthorizedShareToken public planAuthorizedShareToken;
    IAgreementManager public planAgreementManager;
    uint256 public planExpiration;
    address[][] public planModelAgreementTerms;
    address public planOwner;
    Authority public planAuthority;

    function getPlanModelAgreementTerms() external view returns (address[][] memory) {
        return planModelAgreementTerms;
    }

    /// @notice Emitted when a new Stock Plan is deployed.
    /// @param plan The newly deployed Stock Plan.
    /// @param deployer The address of the StockPlan deployer.
    event PlanDeployed(uint256 indexed id, StockPlan indexed plan, address indexed deployer);

    /// @notice Deploy a new Stock Plan.
    /// @return plan The address of the newly deployed plan.
    function deployStockPlan(
        AuthorizedShareToken authorizedShareToken,
        IAgreementManager agreementManager,
        uint256 expiration,
        address[][] memory modelAgreementTerms,
        // slither-disable-next-line naming-convention
        address _owner,
        // slither-disable-next-line naming-convention
        Authority _authority
    ) external returns (StockPlan plan, uint256 index) {
        // Unchecked is safe here because index will never reach type(uint256).max
        unchecked {
            index = planNumber + 1;
        }

        // Update state variables.
        planNumber = index;
        planAuthorizedShareToken = authorizedShareToken;
        planAgreementManager = agreementManager;
        planExpiration = expiration;
        planModelAgreementTerms = modelAgreementTerms;
        planOwner = _owner;
        planAuthority = _authority;

        // Deploy the Stock Plan using the CREATE2 opcode.
        plan = new StockPlan{salt: bytes32(index)}();

        // Emit the event.
        emit PlanDeployed(index, plan, msg.sender);

        // Reset the deployment name.
        delete planAuthorizedShareToken;
        delete planAgreementManager;
        delete planExpiration;
        delete planModelAgreementTerms;
        delete planOwner;
        delete planAuthority;
    }

    /*///////////////////////////////////////////////////////////////
                           RETRIEVAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the address of a Stock Plan given its ID.
    function getPlanFromNumber(uint256 id) external view returns (StockPlan plan) {
        // Retrieve the Stock Plan.
        return
            StockPlan(
                payable(
                    keccak256(
                        abi.encodePacked(
                            // Prefix:
                            bytes1(0xFF),
                            // Creator:
                            address(this),
                            // Salt:
                            bytes32(id),
                            // Bytecode hash:
                            keccak256(
                                abi.encodePacked(
                                    // Deployment bytecode:
                                    type(StockPlan).creationCode
                                )
                            )
                        )
                    ).fromLast20Bytes() // Convert the CREATE2 hash into an address.
                )
            );
    }
}

