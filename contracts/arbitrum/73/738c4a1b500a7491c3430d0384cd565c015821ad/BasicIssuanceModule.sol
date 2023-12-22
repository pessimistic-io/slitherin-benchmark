/*
    Copyright 2020 Set Labs Inc.
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.6.10;
pragma experimental "ABIEncoderV2";

import { IERC20 } from "./IERC20.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { SafeCast } from "./SafeCast.sol";
import { SafeMath } from "./SafeMath.sol";

import { IController } from "./IController.sol";
import { IManagerIssuanceHook } from "./IManagerIssuanceHook.sol";
import { Invoke } from "./Invoke.sol";
import { IJasperVault } from "./IJasperVault.sol";
import { ModuleBase } from "./ModuleBase.sol";
import { Position } from "./Position.sol";
import { PreciseUnitMath } from "./PreciseUnitMath.sol";

/**
 * @title BasicIssuanceModule
 * @author Set Protocol
 *
 * Module that enables issuance and redemption functionality on a JasperVault. This is a module that is
 * required to bring the totalSupply of a Set above 0.
 */
contract BasicIssuanceModule is ModuleBase, ReentrancyGuard {
    using Invoke for IJasperVault;
    using Position for IJasperVault.Position;
    using Position for IJasperVault;
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;
    using SafeCast for int256;

    /* ============ Events ============ */

    event SetTokenIssued(
        address indexed _jasperVault,
        address indexed _issuer,
        address indexed _to,
        address _hookContract,
        uint256 _quantity
    );
    event SetTokenRedeemed(
        address indexed _jasperVault,
        address indexed _redeemer,
        address indexed _to,
        uint256 _quantity
    );

    /* ============ State Variables ============ */

    // Mapping of JasperVault to Issuance hook configurations
    mapping(IJasperVault => IManagerIssuanceHook) public managerIssuanceHook;

    /* ============ Constructor ============ */

    /**
     * Set state controller state variable
     *
     * @param _controller             Address of controller contract
     */
    constructor(IController _controller) public ModuleBase(_controller) {}

    /* ============ External Functions ============ */

    /**
     * Deposits the JasperVault's position components into the JasperVault and mints the JasperVault of the given quantity
     * to the specified _to address. This function only handles Default Positions (positionState = 0).
     *
     * @param _jasperVault             Instance of the JasperVault contract
     * @param _quantity             Quantity of the JasperVault to mint
     * @param _to                   Address to mint JasperVault to
     */
    function issue(
        IJasperVault _jasperVault,
        uint256 _quantity,
        address _to
    )
        external
        nonReentrant
        onlyValidAndInitializedSet(_jasperVault)
    {
        require(_quantity > 0, "Issue quantity must be > 0");

        address hookContract = _callPreIssueHooks(_jasperVault, _quantity, msg.sender, _to);

        (
            address[] memory components,
            uint256[] memory componentQuantities
        ) = getRequiredComponentUnitsForIssue(_jasperVault, _quantity);

        // For each position, transfer the required underlying to the JasperVault
        for (uint256 i = 0; i < components.length; i++) {
            // Transfer the component to the JasperVault
            transferFrom(
                IERC20(components[i]),
                msg.sender,
                address(_jasperVault),
                componentQuantities[i]
            );
        }

        // Mint the JasperVault
        _jasperVault.mint(_to, _quantity);

        emit SetTokenIssued(address(_jasperVault), msg.sender, _to, hookContract, _quantity);
    }

    /**
     * Redeems the JasperVault's positions and sends the components of the given
     * quantity to the caller. This function only handles Default Positions (positionState = 0).
     *
     * @param _jasperVault             Instance of the JasperVault contract
     * @param _quantity             Quantity of the JasperVault to redeem
     * @param _to                   Address to send component assets to
     */
    function redeem(
        IJasperVault _jasperVault,
        uint256 _quantity,
        address _to
    )
        external
        nonReentrant
        onlyValidAndInitializedSet(_jasperVault)
    {
        require(_quantity > 0, "Redeem quantity must be > 0");

        // Burn the JasperVault - ERC20's internal burn already checks that the user has enough balance
        _jasperVault.burn(msg.sender, _quantity);

        // For each position, invoke the JasperVault to transfer the tokens to the user
        address[] memory components = _jasperVault.getComponents();
        for (uint256 i = 0; i < components.length; i++) {
            address component = components[i];
            require(!_jasperVault.hasExternalPosition(component), "Only default positions are supported");

            uint256 unit = _jasperVault.getDefaultPositionRealUnit(component).toUint256();

            // Use preciseMul to round down to ensure overcollateration when small redeem quantities are provided
            uint256 componentQuantity = _quantity.preciseMul(unit);

            // Instruct the JasperVault to transfer the component to the user
            _jasperVault.strictInvokeTransfer(
                component,
                _to,
                componentQuantity
            );
        }

        emit SetTokenRedeemed(address(_jasperVault), msg.sender, _to, _quantity);
    }

    /**
     * Initializes this module to the JasperVault with issuance-related hooks. Only callable by the JasperVault's manager.
     * Hook addresses are optional. Address(0) means that no hook will be called
     *
     * @param _jasperVault             Instance of the JasperVault to issue
     * @param _preIssueHook         Instance of the Manager Contract with the Pre-Issuance Hook function
     */
    function initialize(
        IJasperVault _jasperVault,
        IManagerIssuanceHook _preIssueHook
    )
        external
        onlySetManager(_jasperVault, msg.sender)
        onlyValidAndPendingSet(_jasperVault)
    {
        managerIssuanceHook[_jasperVault] = _preIssueHook;

        _jasperVault.initializeModule();
    }

    /**
     * Reverts as this module should not be removable after added. Users should always
     * have a way to redeem their Sets
     */
    function removeModule() external override {
        revert("The BasicIssuanceModule module cannot be removed");
    }

    /* ============ External Getter Functions ============ */

    /**
     * Retrieves the addresses and units required to mint a particular quantity of JasperVault.
     *
     * @param _jasperVault             Instance of the JasperVault to issue
     * @param _quantity             Quantity of JasperVault to issue
     * @return address[]            List of component addresses
     * @return uint256[]            List of component units required to issue the quantity of SetTokens
     */
    function getRequiredComponentUnitsForIssue(
        IJasperVault _jasperVault,
        uint256 _quantity
    )
        public
        view
        onlyValidAndInitializedSet(_jasperVault)
        returns (address[] memory, uint256[] memory)
    {
        address[] memory components = _jasperVault.getComponents();

        uint256[] memory notionalUnits = new uint256[](components.length);

        for (uint256 i = 0; i < components.length; i++) {
            require(!_jasperVault.hasExternalPosition(components[i]), "Only default positions are supported");

            notionalUnits[i] = _jasperVault.getDefaultPositionRealUnit(components[i]).toUint256().preciseMulCeil(_quantity);
        }

        return (components, notionalUnits);
    }

    /* ============ Internal Functions ============ */

    /**
     * If a pre-issue hook has been configured, call the external-protocol contract. Pre-issue hook logic
     * can contain arbitrary logic including validations, external function calls, etc.
     */
    function _callPreIssueHooks(
        IJasperVault _jasperVault,
        uint256 _quantity,
        address _caller,
        address _to
    )
        internal
        returns(address)
    {
        IManagerIssuanceHook preIssueHook = managerIssuanceHook[_jasperVault];
        if (address(preIssueHook) != address(0)) {
            preIssueHook.invokePreIssueHook(_jasperVault, _quantity, _caller, _to);
            return address(preIssueHook);
        }

        return address(0);
    }
}

