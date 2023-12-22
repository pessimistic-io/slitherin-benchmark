//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {DopexPositionManager} from "./DopexPositionManager.sol";
import {Clones} from "./Clones.sol";
import {ContractWhitelist} from "./ContractWhitelist.sol";
import {Ownable} from "./Ownable.sol";

contract DopexPositionManagerFactory is ContractWhitelist, Ownable {
    address public immutable DopexPositionManagerImplementation;
    address public callback;
    uint256 public minSlipageBps = 350;

    mapping(address => address) public userPositionManagers;

    event CallbackSet(address _callback);
    event CallbackSetPositionManager(
        address _positionManager,
        address _callback
    );
    event MinSlippageBpsSet(uint256 _slippageBps);
    event PositionManagerReferralCodeSet(
        address _positionManager,
        bytes32 _referralCode
    );
    event PositionManagerCallbackSet(
        address _positionManager,
        address _callback
    );
    event PositionManagerStrategyControllerSet(
        address _positionManager,
        address _strategyController
    );

    error CallbackNotSet();

    constructor() {
        DopexPositionManagerImplementation = address(
            new DopexPositionManager()
        );
    }

    function createPositionmanager(
        address _user
    ) external returns (address positionManager) {
        _isEligibleSender();

        if (callback == address(0)) {
            revert CallbackNotSet();
        }

        // Position manager instance
        DopexPositionManager userPositionManager = DopexPositionManager(
            Clones.clone(DopexPositionManagerImplementation)
        );
        userPositionManager.setFactory(address(this));
        userPositionManager.setCallback(callback);

        userPositionManagers[_user] = address(userPositionManager);
        positionManager = address(userPositionManager);
    }

    function setCallback(address _callback) external onlyOwner {
        callback = _callback;
        emit CallbackSet(_callback);
    }

    function setPositionManagerCallback(
        address _positionManager,
        address _callback
    ) external onlyOwner {
        DopexPositionManager(_positionManager).setCallback(_callback);
        emit PositionManagerCallbackSet(_positionManager, _callback);
    }

    function setPositionManagerReferralCode(
        address _positionManager,
        bytes32 _referralCode
    ) external onlyOwner {
        DopexPositionManager(_positionManager).setReferralCode(_referralCode);
        emit PositionManagerReferralCodeSet(_positionManager, _referralCode);
    }

    function setMinSlippageBps(uint256 _slippageBps) external onlyOwner {
        minSlipageBps = _slippageBps;
        emit MinSlippageBpsSet(_slippageBps);
    }

    function setPositionManagerStrategyController(
        address _positionManager,
        address _strategyController
    ) external onlyOwner {
        DopexPositionManager(_positionManager).setStrategyController(
            _strategyController
        );
        emit PositionManagerStrategyControllerSet(
            _positionManager,
            _strategyController
        );
    }

    /**
     * @notice Add a contract to the whitelist
     * @dev    Can only be called by the owner
     * @param _contract Address of the contract that needs to be added to the whitelist
     */
    function addToContractWhitelist(address _contract) external onlyOwner {
        _addToContractWhitelist(_contract);
    }

    /**
     * @notice Add a contract to the whitelist
     * @dev    Can only be called by the owner
     * @param _contract Address of the contract that needs to be added to the whitelist
     */
    function removeFromContractWhitelist(address _contract) external onlyOwner {
        _removeFromContractWhitelist(_contract);
    }
}

