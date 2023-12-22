// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./Initializable.sol";
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

contract ChainlinkUpkeep is KeeperCompatibleInterface, Initializable {
    address public owner;
    address public clRegistry;

    /// Errors
    error UpKeepNotNeeded();

    /// Events
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // V2 Initializer
    function initialize(address _owner, address _clRegistry) public initializer {
        owner = _owner;
        clRegistry = _clRegistry;
    }

    /// modifiers
    modifier onlyRegistry() {
        require(msg.sender == clRegistry, "!authorized");
        _;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "!authorized");
        _;
    }

    /**
     * @notice Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @notice Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTICE Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        _transferOwnership(address(0));
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
        } else if (IKeeperProxy(keeperProxy).collatTrigger()) {
            IKeeperProxy(keeperProxy).rebalanceCollateral();
        } else {
            revert UpKeepNotNeeded();
        }
    }

    /**
     * @notice Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address _newOwner) internal virtual {
        address oldOwner = owner;
        owner = _newOwner;
        emit OwnershipTransferred(oldOwner, _newOwner);
    }
}

