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

import {IERC20} from "./IERC20.sol";
import {SafeCast} from "./SafeCast.sol";
import {SafeMath} from "./SafeMath.sol";
import {SignedSafeMath} from "./SignedSafeMath.sol";

import {AddressArrayUtils} from "./AddressArrayUtils.sol";
import {IController} from "./IController.sol";
import {IModuleIssuanceHook} from "./IModuleIssuanceHook.sol";
import {Invoke} from "./Invoke.sol";
import {IJasperVault} from "./IJasperVault.sol";
import {IStakingAdapter} from "./IStakingAdapter.sol";
import {ModuleBase} from "./ModuleBase.sol";
import {Position} from "./Position.sol";

/**
 * @title StakingModule
 * @author Set Protocol
 *
 * Module that enables managers to stake tokens in external protocols in order to take advantage of token distributions.
 * Managers are in charge of opening and closing staking positions. When issuing new SetTokens the IssuanceModule can call
 * the StakingModule in order to facilitate replicating existing staking positions.
 *
 * The StakingModule works in conjunction with StakingAdapters, in which the claimAdapterID / integrationNames are stored
 * on the integration registry. StakingAdapters for the StakingModule are more functional in nature as the same staking
 * contracts are being used across multiple protocols.
 *
 * An example of staking actions include staking yCRV tokens in CRV Liquidity Gauge
 */
contract StakingModule is ModuleBase, IModuleIssuanceHook {
    using AddressArrayUtils for address[];
    using Invoke for IJasperVault;
    using Position for IJasperVault;
    using SafeCast for int256;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeMath for uint256;
    using Position for uint256;

    /* ============ Events ============ */

    event ComponentStaked(
        IJasperVault indexed _jasperVault,
        IERC20 indexed _component,
        address indexed _stakingContract,
        uint256 _componentPositionUnits,
        IStakingAdapter _adapter
    );

    event ComponentUnstaked(
        IJasperVault indexed _jasperVault,
        IERC20 indexed _component,
        address indexed _stakingContract,
        uint256 _componentPositionUnits,
        IStakingAdapter _adapter
    );

    /* ============ Structs ============ */

    struct StakingPosition {
        bytes32 adapterHash; // Hash of adapter name
        uint256 componentPositionUnits; // The amount of tokens, per Set, being staked on associated staking contract
    }

    struct ComponentPositions {
        address[] stakingContracts; // List of staking contracts component is being staked on
        mapping(address => StakingPosition) positions; // Details of each stakingContract's position
    }

    /* ============ State Variables ============ */
    // Mapping relating JasperVault to a component to a struct holding all the external staking positions for the component
    mapping(IJasperVault => mapping(IERC20 => ComponentPositions))
        internal stakingPositions;

    /* ============ Constructor ============ */

    constructor(IController _controller) public ModuleBase(_controller) {}

    /* ============ External Functions ============ */

    /**
     * MANAGER ONLY: Stake _component in external staking contract. Update state on StakingModule and JasperVault to reflect
     * new position. Manager states the contract they are wishing to stake the passed component in as well as how many
     * position units they wish to stake. Manager must also identify the adapter they wish to use.
     *
     * @param _jasperVault                 Address of JasperVault contract
     * @param _stakeContract            Address of staking contract
     * @param _component                Address of token being staked
     * @param _adapterName              Name of adapter used to interact with staking contract
     * @param _componentPositionUnits   Quantity of token to stake in position units
     */
    function stake(
        IJasperVault _jasperVault,
        address _stakeContract,
        IERC20 _component,
        string memory _adapterName,
        uint256 _componentPositionUnits
    ) external onlyManagerAndValidSet(_jasperVault) {
        require(
            _jasperVault.hasSufficientDefaultUnits(
                address(_component),
                _componentPositionUnits
            ),
            "Not enough component to stake"
        );

        IStakingAdapter adapter = IStakingAdapter(
            getAndValidateAdapter(_adapterName)
        );

        _stake(
            _jasperVault,
            _stakeContract,
            _component,
            adapter,
            _componentPositionUnits,
            _jasperVault.totalSupply()
        );

        _updateStakeState(
            _jasperVault,
            _stakeContract,
            _component,
            _adapterName,
            _componentPositionUnits
        );

        emit ComponentStaked(
            _jasperVault,
            _component,
            _stakeContract,
            _componentPositionUnits,
            adapter
        );
    }

    /**
     * MANAGER ONLY: Unstake _component from external staking contract. Update state on StakingModule and JasperVault to reflect
     * new position.
     *
     * @param _jasperVault                 Address of JasperVault contract
     * @param _stakeContract            Address of staking contract
     * @param _component                Address of token being staked
     * @param _adapterName              Name of adapter used to interact with staking contract
     * @param _componentPositionUnits   Quantity of token to unstake in position units
     */
    function unstake(
        IJasperVault _jasperVault,
        address _stakeContract,
        IERC20 _component,
        string memory _adapterName,
        uint256 _componentPositionUnits
    ) external onlyManagerAndValidSet(_jasperVault) {
        require(
            getStakingPositionUnit(_jasperVault, _component, _stakeContract) >=
                _componentPositionUnits,
            "Not enough component tokens staked"
        );

        IStakingAdapter adapter = IStakingAdapter(
            getAndValidateAdapter(_adapterName)
        );

        _unstake(
            _jasperVault,
            _stakeContract,
            _component,
            adapter,
            _componentPositionUnits,
            _jasperVault.totalSupply()
        );

        _updateUnstakeState(
            _jasperVault,
            _stakeContract,
            _component,
            _componentPositionUnits
        );

        emit ComponentUnstaked(
            _jasperVault,
            _component,
            _stakeContract,
            _componentPositionUnits,
            adapter
        );
    }

    /**
     * MODULE ONLY: On issuance, replicates all staking positions for a given component by staking the component transferred into
     * the JasperVault by an issuer. The amount staked should only be the notional amount required to replicate a _setTokenQuantity
     * amount of a position. No updates to positions should take place.
     *
     * @param _jasperVault                 Address of JasperVault contract
     * @param _component                Address of token being staked
     * @param _setTokenQuantity         Quantity of JasperVault being issued
     */
    function componentIssueHook(
        IJasperVault _jasperVault,
        uint256 _setTokenQuantity,
        IERC20 _component,
        bool /* _isEquity */
    ) external override onlyModule(_jasperVault) {
        address[] memory stakingContracts = getStakingContracts(
            _jasperVault,
            _component
        );
        for (uint256 i = 0; i < stakingContracts.length; i++) {
            // NOTE: We assume here that the calling module has transferred component tokens to the JasperVault from the issuer
            StakingPosition memory stakingPosition = getStakingPosition(
                _jasperVault,
                _component,
                stakingContracts[i]
            );

            _stake(
                _jasperVault,
                stakingContracts[i],
                _component,
                IStakingAdapter(
                    getAndValidateAdapterWithHash(stakingPosition.adapterHash)
                ),
                stakingPosition.componentPositionUnits,
                _setTokenQuantity
            );
        }
    }

    /**
     * MODULE ONLY: On redemption, unwind all staking positions for a given asset by unstaking the given component. The amount
     * unstaked should only be the notional amount required to unwind a _setTokenQuantity amount of a position. No updates to
     * positions should take place.
     *
     * @param _jasperVault                 Address of JasperVault contract
     * @param _component                Address of token being staked
     * @param _setTokenQuantity         Quantity of JasperVault being issued
     */
    function componentRedeemHook(
        IJasperVault _jasperVault,
        uint256 _setTokenQuantity,
        IERC20 _component,
        bool /* _isEquity */
    ) external override onlyModule(_jasperVault) {
        address[] memory stakingContracts = getStakingContracts(
            _jasperVault,
            _component
        );
        for (uint256 i = 0; i < stakingContracts.length; i++) {
            StakingPosition memory stakingPosition = getStakingPosition(
                _jasperVault,
                _component,
                stakingContracts[i]
            );

            _unstake(
                _jasperVault,
                stakingContracts[i],
                _component,
                IStakingAdapter(
                    getAndValidateAdapterWithHash(stakingPosition.adapterHash)
                ),
                stakingPosition.componentPositionUnits,
                _setTokenQuantity
            );
        }
    }

    function moduleIssueHook(
        IJasperVault _jasperVault,
        uint256 _setTokenQuantity
    ) external override {}

    function moduleRedeemHook(
        IJasperVault _jasperVault,
        uint256 _setTokenQuantity
    ) external override {}

    /**
     * Initializes this module to the JasperVault. Only callable by the JasperVault's manager.
     *
     * @param _jasperVault             Instance of the JasperVault to issue
     */
    function initialize(
        IJasperVault _jasperVault
    )
        external
        onlySetManager(_jasperVault, msg.sender)
        onlyValidAndPendingSet(_jasperVault)
    {
        _jasperVault.initializeModule();
    }

    /**
     * Removes this module from the JasperVault, via call by the JasperVault. If an outstanding staking position remains using
     * this module then it cannot be removed. Outstanding staking must be closed out first before removal.
     */
    function removeModule() external override {
    }

    /* ============ External Getter Functions ============ */

    function hasStakingPosition(
        IJasperVault _jasperVault,
        IERC20 _component,
        address _stakeContract
    ) public view returns (bool) {
        return
            getStakingContracts(_jasperVault, _component).contains(
                _stakeContract
            );
    }

    function getStakingContracts(
        IJasperVault _jasperVault,
        IERC20 _component
    ) public view returns (address[] memory) {
        return stakingPositions[_jasperVault][_component].stakingContracts;
    }

    function getStakingPosition(
        IJasperVault _jasperVault,
        IERC20 _component,
        address _stakeContract
    ) public view returns (StakingPosition memory) {
        return
            stakingPositions[_jasperVault][_component].positions[
                _stakeContract
            ];
    }

    function getStakingPositionUnit(
        IJasperVault _jasperVault,
        IERC20 _component,
        address _stakeContract
    ) public view returns (uint256) {
        return
            getStakingPosition(_jasperVault, _component, _stakeContract)
                .componentPositionUnits;
    }

    /* ============ Internal Functions ============ */

    /**
     * Stake _component in external staking contract.
     *
     * @param _jasperVault                 Address of JasperVault contract
     * @param _stakeContract            Address of staking contract
     * @param _component                Address of token being staked
     * @param _adapter                  Address of adapter used to interact with staking contract
     * @param _componentPositionUnits   Quantity of token to stake in position units
     * @param _setTokenStakeQuantity    Quantity of SetTokens to stake
     */
    function _stake(
        IJasperVault _jasperVault,
        address _stakeContract,
        IERC20 _component,
        IStakingAdapter _adapter,
        uint256 _componentPositionUnits,
        uint256 _setTokenStakeQuantity
    ) internal {
        uint256 notionalStakeQuantity = _setTokenStakeQuantity
            .getDefaultTotalNotional(_componentPositionUnits);

        address spender = _adapter.getSpenderAddress(_stakeContract);

        _jasperVault.invokeApprove(
            address(_component),
            spender,
            notionalStakeQuantity
        );

        (address target, uint256 callValue, bytes memory methodData) = _adapter
            .getStakeCallData(_stakeContract, notionalStakeQuantity);

        _jasperVault.invoke(target, callValue, methodData);
    }

    /**
     * Unstake position from external staking contract and validates expected components were received.
     *
     * @param _jasperVault                 Address of JasperVault contract
     * @param _stakeContract            Address of staking contract
     * @param _component                Address of token being unstaked
     * @param _adapter                  Address of adapter used to interact with staking contract
     * @param _componentPositionUnits   Quantity of token to unstake in position units
     */
    function _unstake(
        IJasperVault _jasperVault,
        address _stakeContract,
        IERC20 _component,
        IStakingAdapter _adapter,
        uint256 _componentPositionUnits,
        uint256 _setTokenUnstakeQuantity
    ) internal {
        uint256 preActionBalance = _component.balanceOf(address(_jasperVault));

        uint256 notionalUnstakeQuantity = _setTokenUnstakeQuantity
            .getDefaultTotalNotional(_componentPositionUnits);
        (address target, uint256 callValue, bytes memory methodData) = _adapter
            .getUnstakeCallData(_stakeContract, notionalUnstakeQuantity);

        _jasperVault.invoke(target, callValue, methodData);

        uint256 postActionBalance = _component.balanceOf(address(_jasperVault));
        require(
            preActionBalance.add(notionalUnstakeQuantity) <= postActionBalance,
            "Not enough tokens returned from stake contract"
        );
    }

    /**
     * Update positions on JasperVault and tracking on StakingModule after staking is complete. Includes the following updates:
     *  - If adding to position then add positionUnits to existing position amount on StakingModule
     *  - If opening new staking position add stakeContract to stakingContracts list and create position entry in position mapping
     *    (on StakingModule)
     *  - Subtract from Default position of _component on JasperVault
     *  - Add to external position of _component on JasperVault referencing this module
     *
     * @param _jasperVault                 Address of JasperVault contract
     * @param _stakeContract            Address of staking contract
     * @param _component                Address of token being unstaked
     * @param _adapterName              Address of adapter used to interact with staking contract
     * @param _componentPositionUnits   Quantity of token to stake in position units
     */
    function _updateStakeState(
        IJasperVault _jasperVault,
        address _stakeContract,
        IERC20 _component,
        string memory _adapterName,
        uint256 _componentPositionUnits
    ) internal {
        if (hasStakingPosition(_jasperVault, _component, _stakeContract)) {
            stakingPositions[_jasperVault][_component]
                .positions[_stakeContract]
                .componentPositionUnits = _componentPositionUnits.add(
                getStakingPositionUnit(_jasperVault, _component, _stakeContract)
            );
        } else {
            stakingPositions[_jasperVault][_component].stakingContracts.push(
                _stakeContract
            );
            stakingPositions[_jasperVault][_component].positions[
                _stakeContract
            ] = StakingPosition({
                componentPositionUnits: _componentPositionUnits,
                adapterHash: getNameHash(_adapterName)
            });
        }

        uint256 newDefaultTokenUnit = _jasperVault
            .getDefaultPositionRealUnit(address(_component))
            .toUint256()
            .sub(_componentPositionUnits);
        _jasperVault.editDefaultPosition(
            address(_component),
            newDefaultTokenUnit
        );

        int256 newExternalTokenUnit = _jasperVault
            .getExternalPositionRealUnit(address(_component), address(this))
            .add(_componentPositionUnits.toInt256());
        _jasperVault.editExternalPosition(
            address(_component),
            address(this),
            newExternalTokenUnit,
            ""
        );
    }

    /**
     * Update positions on JasperVault and tracking on StakingModule after unstaking is complete. Includes the following updates:
     *  - If paring down position then subtract positionUnits from existing position amount on StakingModule
     *  - If closing staking position remove _stakeContract from stakingContracts list and delete position entry in position mapping
     *    (on StakingModule)
     *  - Add to Default position of _component on JasperVault
     *  - Subtract from external position of _component on JasperVault referencing this module
     *
     * @param _jasperVault                 Address of JasperVault contract
     * @param _stakeContract            Address of staking contract
     * @param _component                Address of token being unstaked
     * @param _componentPositionUnits   Quantity of token to stake in position units
     */
    function _updateUnstakeState(
        IJasperVault _jasperVault,
        address _stakeContract,
        IERC20 _component,
        uint256 _componentPositionUnits
    ) internal {
        uint256 remainingPositionUnits = getStakingPositionUnit(
            _jasperVault,
            _component,
            _stakeContract
        ).sub(_componentPositionUnits);

        if (remainingPositionUnits > 0) {
            stakingPositions[_jasperVault][_component]
                .positions[_stakeContract]
                .componentPositionUnits = remainingPositionUnits;
        } else {
            stakingPositions[_jasperVault][_component]
                .stakingContracts = getStakingContracts(
                _jasperVault,
                _component
            ).remove(_stakeContract);
            delete stakingPositions[_jasperVault][_component].positions[
                _stakeContract
            ];
        }

        uint256 newTokenUnit = _jasperVault
            .getDefaultPositionRealUnit(address(_component))
            .toUint256()
            .add(_componentPositionUnits);

        _jasperVault.editDefaultPosition(address(_component), newTokenUnit);

        int256 newExternalTokenUnit = _jasperVault
            .getExternalPositionRealUnit(address(_component), address(this))
            .sub(_componentPositionUnits.toInt256());

        _jasperVault.editExternalPosition(
            address(_component),
            address(this),
            newExternalTokenUnit,
            ""
        );
    }
}

