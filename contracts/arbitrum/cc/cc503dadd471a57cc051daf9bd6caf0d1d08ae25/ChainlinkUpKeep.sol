// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./KeeperCompatible.sol";

interface IKeeperProxy {
    // Strategy Wrappers
    function rebalanceDebt() external;
    function rebalanceCollateral() external;

    function strategist() external view returns (address);

    // Proxy Keeper Functions
    function collatTrigger() external view returns (bool _canExec);
    function debtTrigger() external view returns (bool _canExec);
    function collatTriggerHysteria() external view returns (bool _canExec);
    function debtTriggerHysteria() external view returns (bool _canExec);
}

contract ChainlinkUpkeep is Initializable, KeeperCompatibleInterface, OwnableUpgradeable {
    address public clRegistry;

    // V2 Initializer
    function initialize(address _owner, address _clRegistry) public initializer {
        _transferOwnership(_owner);
        clRegistry = _clRegistry;
    }

    /// modifiers
    modifier onlyRegistry() {
        require(msg.sender == clRegistry, "!authorized");
        _;
    }
   
    /**
     * @notice Sets the Chainlink Registry
     */
    function setclRegistry(address _clRegistry) external onlyOwner {
        require(_clRegistry != address(0), "_clRegistry is the zero address");
        clRegistry = _clRegistry;
    }

    /**
     * @notice see KeeperCompatibleInterface.sol
     */
    function checkUpkeep(bytes calldata _checkData) external view override returns (bool _upkeepNeeded, bytes memory _performData) {
        address keeperProxy = abi.decode(_checkData, (address));
        
        /// first we check debt trigger, if debt rebalance doesn't need to be checked then we check collat trigger
        _upkeepNeeded = IKeeperProxy(keeperProxy).debtTriggerHysteria();
        if (_upkeepNeeded) {
            _performData = abi.encode(keeperProxy);
        } else {
            _upkeepNeeded = IKeeperProxy(keeperProxy).collatTriggerHysteria();
            if (_upkeepNeeded) {
                _performData = abi.encode(keeperProxy);
            }
        }
    }

    /**
     * @notice see KeeperCompatibleInterface.sol
     */
    function performUpkeep(bytes calldata _performData) external override onlyRegistry {
        address keeperProxy = abi.decode(_performData, (address));
        if (IKeeperProxy(keeperProxy).debtTrigger()) {
            IKeeperProxy(keeperProxy).rebalanceDebt();
        } else {
            IKeeperProxy(keeperProxy).rebalanceCollateral();
        }
    }
}

