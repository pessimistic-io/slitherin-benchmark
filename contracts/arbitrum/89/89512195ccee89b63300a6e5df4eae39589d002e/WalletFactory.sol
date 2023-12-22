// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./Wallet.sol";
import "./Proxy.sol";

import "./ClonesUpgradeable.sol";

/// @title WalletFactory
/// @notice Creates new `Wallet`s.
contract WalletFactory {
    using AddressUpgradeable for address;

    /// @notice The relay guardian.
    /// WARNING: If this variable is set to the zero address, the relay guardian whitelist will NOT be validated on wallets--so do NOT set this variable to the zero address unless you are sure you want to allow anyone to relay transactions.
    /// The relay guardian relays all transactions for a `Wallet`, unless the relay guardian whitelist is deactivated on a `Wallet` or if the relay guardian is set to the zero address here, in which case any address can relay transactions.
    /// The relay guardian can act as off-chain transaction policy node(s) permitting realtime/AI-based fraud detection, symmetric/access-token-based authentication mechanisms, and/or instant onboarding to the Waymont chain.
    /// The relay guardian whitelist can be disabled/enabled via a user-specified timelock on the `Wallet`.
    address public relayGuardian;

    /// @notice The secondary relay guardian.
    /// WARNING: Even if the secondary guardian is set, if the primary guardian is not set, the `Wallet` contract does not validate that the relayer is a whitelisted guardian.
    /// The secondary relay guardian is used as a fallback guardian.
    /// However, it can also double as an authenticated multicall contract to save gas while relaying transactions across multiple wallets in the same blocks.
    /// If using a secondary relay guardian, ideally, it is the less-used of the two guardians to conserve some gas.
    address public secondaryRelayGuardian;

    /// @notice The relay guardian manager.
    address public relayGuardianManager;

    /// @dev `Wallet` implementation/logic contract address.
    address public immutable walletImplementation;

    /// @notice Event emitted when the relay guardian is changed.
    event RelayGuardianChanged(address _relayGuardian);

    /// @notice Event emitted when the secondary relay guardian is changed.
    event SecondaryRelayGuardianChanged(address _relayGuardian);

    /// @notice Event emitted when the relay guardian manager is changed.
    event RelayGuardianManagerChanged(address _relayGuardianManager);

    /// @dev Constructor to initialize the factory by setting the relay guardian manager and creating and setting a new `Wallet` implementation.
    constructor(address _relayGuardianManager) {
        relayGuardianManager = _relayGuardianManager;
        emit RelayGuardianManagerChanged(_relayGuardianManager);
        walletImplementation = address(new Wallet());
    }

    /// @notice Deploys an upgradeable (or non-upgradeable) proxy over `Wallet`.
    /// WARNING: Does not validate that signers have >= threshold votes.
    /// Only callable by the relay guardian so nonces used on other chains can be kept unused on this chain until the same user deploys to this chain.
    /// @param nonce The unique nonce of the wallet to create. If the contract address of the `WalletFactory` and the `Wallet` implementation is the same across each chain (which it will be if the same private key deploys them with the same nonces), then the contract addresses of the wallets created will also be the same across all chains.
    /// @param signers Signers can be password-derived keys generated using bcrypt.
    /// @param signerConfigs Controls votes per signer as well as signing timelocks.
    /// @param threshold Threshold of votes required to sign transactions.
    /// @param relayerWhitelistTimelock Applies to disabling the relayer whitelist. If set to zero, the relayer whitelist is disabled.
    /// @param subscriptionPaymentsEnabled Whether or not automatic subscription payments are enabled (disabled if credit card payments are enabled off-chain).
    /// @param upgradeable Whether or not the contract is upgradeable (costs less gas to deploy and use if not).
    function createWallet(
        uint256 nonce,
        address[] calldata signers,
        Wallet.SignerConfig[] calldata signerConfigs,
        uint8 threshold,
        uint256 relayerWhitelistTimelock,
        bool subscriptionPaymentsEnabled,
        bool upgradeable
    ) external returns (Wallet) {
        require(msg.sender == relayGuardian || msg.sender == secondaryRelayGuardian, "Sender is not the relay guardian.");
        Wallet instance = Wallet(upgradeable ? payable(new Proxy{salt: bytes32(nonce)}(walletImplementation)) : payable(ClonesUpgradeable.cloneDeterministic(walletImplementation, bytes32(nonce))));
        instance.initialize(signers, signerConfigs, threshold, relayerWhitelistTimelock, subscriptionPaymentsEnabled);
        return instance;
    }

    /// @dev Access control for the relay guardian manager.
    modifier onlyRelayGuardianManager() {
        require(msg.sender == relayGuardianManager, "Sender is not the relay guardian manager.");
        _;
    }

    /// @notice Sets the relay guardian.
    /// WARNING: If this variable is set to the zero address, the relay guardian whitelist will NOT be validated on wallets--so do NOT set this variable to the zero address unless you are sure you want to allow anyone to relay transactions.
    function setRelayGuardian(address _relayGuardian) external onlyRelayGuardianManager {
        relayGuardian = _relayGuardian;
        emit RelayGuardianChanged(_relayGuardian);
    }

    /// @notice Sets the secondary relay guardian.
    /// WARNING: Even if the secondary guardian is set, if the primary guardian is not set, the `Wallet` contract does not validate that the relayer is a whitelisted guardian.
    function setSecondaryRelayGuardian(address _relayGuardian) external onlyRelayGuardianManager {
        secondaryRelayGuardian = _relayGuardian;
        emit SecondaryRelayGuardianChanged(_relayGuardian);
    }

    /// @notice Sets the relay guardian manager.
    function setRelayGuardianManager(address _relayGuardianManager) external onlyRelayGuardianManager {
        relayGuardianManager = _relayGuardianManager;
        emit RelayGuardianManagerChanged(_relayGuardianManager);
    }

    /// @dev Validates that `sender` is a valid relay guardian.
    function checkRelayGuardian(address sender) external view {
        address _relayGuardian = relayGuardian;
        require(sender == _relayGuardian || sender == secondaryRelayGuardian || _relayGuardian == address(0), "Sender is not relay guardian.");
    }
}

