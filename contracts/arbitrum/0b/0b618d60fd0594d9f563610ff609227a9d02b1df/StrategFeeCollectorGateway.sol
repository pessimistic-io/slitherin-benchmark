// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "./AccessControlUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IStrategPortal.sol";

contract StrategFeeCollectorGateway is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    address public portal;
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    event PortalSwapExecuted(
        IStrategPortal.SwapIntegration route,
        address sourceAsset,
        address targetAsset,
        uint256 amount
    );

    event PortalBridgeExecuted(
        IStrategPortal.SwapIntegration route,
        address sourceAsset,
        address targetAsset,
        uint256 amount,
        uint256 targetChain
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address treasury,
        address _portal
    ) initializer public {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, treasury);
        _grantRole(DEPLOYER_ROLE, msg.sender);

        portal = _portal; 
    }

    function portalSwap(
        IStrategPortal.SwapIntegration _route,
        address _sourceAsset,
        address _targetAsset,
        uint256 _amount,
        bytes calldata _routeParams
    ) external onlyRole(DEPLOYER_ROLE) {
        IERC20(_sourceAsset).safeApprove(portal, _amount);
        IStrategPortal(portal).swap(
            false,
            false,
            _route,
            _sourceAsset,
            _targetAsset,
            _amount,
            "", 
            _routeParams
        );

        emit PortalSwapExecuted(
            _route,
            _sourceAsset,
            _targetAsset,
            _amount
        );
    }

    function portalBridge(
        IStrategPortal.SwapIntegration _route,
        address _sourceAsset,
        address _targetAsset,
        uint256 _amount,
        uint256 _targetChain,
        bytes calldata _routeParams
    ) external onlyRole(DEPLOYER_ROLE) {
        IERC20(_sourceAsset).safeApprove(portal, _amount);
        IStrategPortal(portal).swapAndBridge(
            false,
            false,
            _route,
            _sourceAsset,
            _targetAsset,
            _amount,
            _targetChain,
            "", 
            _routeParams
        );

        emit PortalBridgeExecuted(
            _route,
            _sourceAsset,
            _targetAsset,
            _amount,
            _targetChain
        );
    }

}
