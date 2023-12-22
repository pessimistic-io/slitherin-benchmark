// SPDX-License-Identifier: BSD-3-Clause
// Copyright © 2023 TXA PTE. LTD.
pragma solidity 0.8.19;

import "./FeeManager.sol";
import "./IProcessingChainManager.sol";
// import "../../Rollup/Rollup.sol";
// import "../../CrossChain/LayerZero/ProcessingChainLz.sol";
// import "./WalletDelegation.sol";
// import "../../Oracle/Oracle.sol";

/// The ProcessingChainManager is deployed on the processing chain.
/// It handles deployment of core protocol contracts, authorizes addresses to perform actions across the protocol, and
/// stores protocol parameters.
/// Each contract on the processing chain defers to the ProcessingChainManager for determining
contract ProcessingChainManager is IProcessingChainManager, FeeManager {
    address public admin;
    address public insuranceFund;
    address public participatingInterface;
    address public rollup;
    address public fraudEngine;
    address public staking;
    address public walletDelegation;
    address public relayer;
    address public oracle;
    address public stablecoin;
    address public protocolToken;

    /// Number of blocks that must pass after a state root is submitted in Rollup before it can be confirmed.
    uint256 public fraudPeriod = 28_800; // ~ 4 days on Ethereum
    /// Amount of protocol token that must be locked to propose a state root
    uint256 public rootProposalLockAmount = 10_000e18;
    /// Maps chain ID to boolean indicated whether or not this EVM chain is supported by the protocol.
    mapping(uint256 => bool) public supportedChains;
    /// Maps chain ID to token address to decimals of precision
    /// A value of zero means this asset is not supported
    mapping(uint256 => mapping(address => uint8)) public supportedAsset;
    /// Maps address to boolean indicating whether or not it's authorized as a validator
    mapping(address => bool) public validators;

    constructor(
        address _admin,
        address _participatingInterface,
        address _validator,
        address _stablecoin,
        address _protocolToken
    ) {
        admin = _admin;
        participatingInterface = _participatingInterface;
        // rollup = address(new Rollup(_participatingInterface, address(this)));
        // walletDelegation = address(new WalletDelegation(_participatingInterface, address(this)));
        stablecoin = _stablecoin;
        protocolToken = _protocolToken;
        validators[_validator] = true;
    }

    address public newAdmin;

    function transferAdmin(address _admin) external {
        if (msg.sender != admin) revert("Sender not admin");
        if(_admin == address(0)) revert("New admin cannot be empty");
        if(newAdmin != address(0)) revert("New admin already set");
        newAdmin = _admin;
    }

    function cancelAdminTransfer() external {
        if (msg.sender != admin) revert("Sender not admin");
        newAdmin = address(0);
    }

    function acceptAdminTransfer() external {
        if(msg.sender != newAdmin) revert("Sender not new admin");
        admin = newAdmin;
        newAdmin = address(0);
    }

    function replaceRelayer(address _relayer) external {
        if (msg.sender != admin) revert("Sender not admin");
        if (_relayer == address(0)) revert();
        relayer = _relayer;
    }

    function replaceWalletDelegation(address _walletDelegation) external {
        if (msg.sender != admin) revert("Sender not admin");
        if (_walletDelegation == address(0)) revert();
        walletDelegation = _walletDelegation;
    }

    function replaceOracle(address _oracle) external {
        if (msg.sender != admin) revert("Sender not admin");
        oracle = _oracle;
    }

    function setFraudEngine(address _fraudEngine) external {
        if (msg.sender != admin) revert("Sender not admin");
        if (fraudEngine != address(0)) revert();
        fraudEngine = _fraudEngine;
    }

    function replaceFraudEngine(address _fraudEngine) external {
        if (msg.sender != admin) revert("Sender not admin");
        if (_fraudEngine == address(0)) revert();
        fraudEngine = _fraudEngine;
    }

    function setStaking(address _staking) external {
        if (msg.sender != admin) revert("Sender not admin");
        if (staking != address(0)) revert();
        staking = _staking;
    }

    function replaceStaking(address _staking) external {
        if (msg.sender != admin) revert("Sender not admin");
        if (_staking == address(0)) revert();
        staking = _staking;
    }

    function replaceRollup(address _rollup) external {
        if (msg.sender != admin) revert("Sender not admin");
        if (_rollup == address(0)) revert();
        rollup = _rollup;
    }

    function replaceParticipatingInterface(address _participatingInterface) external {
        if (msg.sender != admin) revert("Sender not admin");
        participatingInterface = _participatingInterface;
    }

    function grantValidator(address _validator) external {
        if (msg.sender != admin) revert("Sender not admin");
        validators[_validator] = true;
    }

    function revokeValidator(address _validator) external {
        if (msg.sender != admin) revert("Sender not admin");
        validators[_validator] = false;
    }

    function updateInsuranceFund(address _insuranceFund) external {
        if (msg.sender != admin) revert("Sender not admin");
        if (_insuranceFund == address(0)) revert();
        insuranceFund = _insuranceFund;
    }

    /// Called by the admin to add support for a new chain
    /// @param _chainId Chain ID of the new EVM chain supported by the protocol
    function addSupportedChain(uint256 _chainId) external {
        if (msg.sender != admin) revert("Sender not admin");
        if (supportedChains[_chainId]) revert();
        supportedChains[_chainId] = true;
    }

    /// Called by admin to support a new asset on the protocol.
    /// If an asset is added here, it should also be added on the corresponding chain's manager.
    /// @param _chainId Chain ID of the asset being added
    /// @param _asset Token address of the assset being added
    /// @param _precision Decimals of precision for the asset being added
    function addSupportedAsset(uint256 _chainId, address _asset, uint8 _precision) external {
        if (msg.sender != admin) revert("Only admin");
        if (!supportedChains[_chainId]) revert("Chain ID not supported");
        if (supportedAsset[_chainId][_asset] != 0) revert("Asset already supported");
        if (_precision == 0) revert("Precision cannot be 0");
        supportedAsset[_chainId][_asset] = _precision;
    }

    /// Called by admin to update the amount of the protocol token a validator needs to lock in order to propose a state
    /// root.
    /// @param _rootProposalLockAmount Updated amount of protocol token a validator must lock to propose a state root
    function updateRootProposalLockAmount(uint256 _rootProposalLockAmount) external {
        if (msg.sender != admin) revert("Only admin");
        if (_rootProposalLockAmount == 0) revert("Lock amount cannot be 0");
        rootProposalLockAmount = _rootProposalLockAmount;
    }

    /// Called by the participating interface to propose new trading fees.
    /// See `FeeManager.sol` for `_proposeFees`
    /// @param _makerFee Numerator of the new maker fee
    /// @param _takerFee Numerator of the new taker fee
    function proposeFees(uint256 _makerFee, uint256 _takerFee) external override {
        if (msg.sender != participatingInterface) revert();
        _proposeFees(_makerFee, _takerFee);
    }

    /// Called by the participating interface to activate proposed trading fees.
    /// See `FeeManager.sol` for `_updateFees`
    function updateFees() external override {
        if (msg.sender != participatingInterface) revert();
        _updateFees();
    }

    /// View function to determine if an address is authorized to be a validator
    function isValidator(address _validator) external view returns (bool) {
        return validators[_validator];
    }

    /// View function to show whether an asset is supported or not.
    function isSupportedAsset(uint256 _chainId, address _asset) external view returns (bool) {
        return supportedAsset[_chainId][_asset] > 0;
    }
}

