// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Initializable } from "./Initializable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { ProxyAdmin } from "./ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";
import { ERC1967Proxy } from "./ERC1967Proxy.sol";
import { IStrategy } from "./IStrategy.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

interface IFactorVault {
    function initialize(
        string memory _name,
        string memory _symbol,
        address _strategy,
        uint256 _upgradeTimelock
    ) external;

    function asset() external view returns (IERC20);

    function deposit(uint256 amount, address receiver) external;
}

interface IOwnable {
    function transferOwnership(address) external;
}

contract FactorVaultManager is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // =============================================================
    //                          Events
    // =============================================================

    event VaultCreated(address indexed vault, address strategy, string name, string symbol, uint256 approval);
    event UpgradeRegistered(address baseImpl, address upgradeImpl);
    event UpgradeRemoved(address baseImpl, address upgradeImpl);
    event UpgradeTimelockChanged(uint256 upgradeTimelock);

    // =============================================================
    //                          Errors
    // =============================================================

    error WRONG_NONCE(); // 0x19f29b44
    error WRONG_VAULT(); // 0x957ca90e
    error STRATEGY_INIT_ERROR(); // 0xc4cfa0b8

    // =============================================================
    //                      State Variables
    // =============================================================

    uint256 public nonce;

    address public vaultImplementation;

    uint256 public upgradeTimelock;

    mapping(address => mapping(address => bool)) internal isUpgrade;

    // =============================================================
    //                      Functions
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _vaultImplementation, uint256 _upgradeTimelock) public initializer {
        __Ownable_init();
        vaultImplementation = _vaultImplementation;
        upgradeTimelock = _upgradeTimelock;
    }

    function deployVault(
        string memory name,
        string memory symbol,
        address strategyImplementation,
        bytes calldata strategyInit,
        uint256 newNonce
    ) external onlyOwner returns (address vault, address strategy) {
        if (newNonce != nonce + 1) revert WRONG_NONCE();

        // deploy vault & strategy with create2
        vault = address(new ERC1967Proxy{ salt: bytes32(newNonce) }(vaultImplementation, ''));
        strategy = address(new ERC1967Proxy(strategyImplementation, ''));

        // init vault
        IFactorVault(vault).initialize(name, symbol, strategy, upgradeTimelock);

        // init strategy
        (bool success, bytes memory result) = strategy.call(strategyInit);
        if (!success) {
            if (result.length < 68) revert STRATEGY_INIT_ERROR();
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }

        // validate address after init
        if (vault != IStrategy(strategy).vault()) revert WRONG_VAULT();

        // deposit 1000 wei to prevent frontrun & inflation/donation attack
        IFactorVault(vault).asset().safeTransferFrom(msg.sender, address(this), 1000);
        IFactorVault(vault).asset().approve(vault, 1000);
        // make stuck 1000 wei in the vault forever
        IFactorVault(vault).deposit(1000, vault);

        // transfer ownership
        IOwnable(vault).transferOwnership(msg.sender);
        IOwnable(strategy).transferOwnership(msg.sender);

        // add nonce
        nonce++;

        emit VaultCreated(vault, strategy, name, symbol, upgradeTimelock);
    }

    // =============================================================
    //                      Settings
    // =============================================================

    function setUpgradeTimelock(uint256 _upgradeTimelock) external onlyOwner {
        upgradeTimelock = _upgradeTimelock;

        emit UpgradeTimelockChanged(_upgradeTimelock);
    }

    // =============================================================
    //                      Create2
    // =============================================================

    // compute next vault address
    function getNextVaultAddress(uint256 _nonce) public view returns (address) {
        bytes memory bytecode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(vaultImplementation, ''));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), _nonce, keccak256(bytecode)));
        return address(uint160(uint(hash)));
    }

    // =============================================================
    //                      Upgrade
    // =============================================================

    function isRegisteredUpgrade(
        address baseImplementation,
        address upgradeImplementation
    ) external view returns (bool) {
        return isUpgrade[baseImplementation][upgradeImplementation];
    }

    function registerUpgrade(address baseImplementation, address upgradeImplementation) external onlyOwner {
        isUpgrade[baseImplementation][upgradeImplementation] = true;

        emit UpgradeRegistered(baseImplementation, upgradeImplementation);
    }

    function removeUpgrade(address baseImplementation, address upgradeImplementation) external onlyOwner {
        delete isUpgrade[baseImplementation][upgradeImplementation];

        emit UpgradeRemoved(baseImplementation, upgradeImplementation);
    }

    function updateImplementation(address _vaultImplementation) external onlyOwner {
        vaultImplementation = _vaultImplementation;
    }
}

