// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./wallet_EtherspotWallet.sol";

contract $EtherspotWallet is EtherspotWallet {
    bytes32 public __hh_exposed_bytecode_marker = "hardhat-exposed";

    event return$_validateSignature(uint256 validationData);

    constructor() {}

    function $MULTIPLY_FACTOR() external pure returns (uint128) {
        return MULTIPLY_FACTOR;
    }

    function $SIXTY_PERCENT() external pure returns (uint16) {
        return SIXTY_PERCENT;
    }

    function $_IMPLEMENTATION_SLOT() external pure returns (bytes32) {
        return _IMPLEMENTATION_SLOT;
    }

    function $_ADMIN_SLOT() external pure returns (bytes32) {
        return _ADMIN_SLOT;
    }

    function $_BEACON_SLOT() external pure returns (bytes32) {
        return _BEACON_SLOT;
    }

    function $SIG_VALIDATION_FAILED() external pure returns (uint256) {
        return SIG_VALIDATION_FAILED;
    }

    function $_initialize(IEntryPoint anEntryPoint,address anOwner) external {
        super._initialize(anEntryPoint,anOwner);
    }

    function $_call(address target,uint256 value,bytes calldata data) external {
        super._call(target,value,data);
    }

    function $_validateSignature(UserOperation calldata userOp,bytes32 userOpHash) external returns (uint256 validationData) {
        (validationData) = super._validateSignature(userOp,userOpHash);
        emit return$_validateSignature(validationData);
    }

    function $_authorizeUpgrade(address newImplementation) external view {
        super._authorizeUpgrade(newImplementation);
    }

    function $_addOwner(address _newOwner) external {
        super._addOwner(_newOwner);
    }

    function $_addGuardian(address _newGuardian) external {
        super._addGuardian(_newGuardian);
    }

    function $_removeOwner(address _owner) external {
        super._removeOwner(_owner);
    }

    function $_removeGuardian(address _guardian) external {
        super._removeGuardian(_guardian);
    }

    function $_checkIfSigned(uint256 _proposalId) external view returns (bool ret0) {
        (ret0) = super._checkIfSigned(_proposalId);
    }

    function $_checkQuorumReached(uint256 _proposalId) external view returns (bool ret0) {
        (ret0) = super._checkQuorumReached(_proposalId);
    }

    function $_disableInitializers() external {
        super._disableInitializers();
    }

    function $_getInitializedVersion() external view returns (uint8 ret0) {
        (ret0) = super._getInitializedVersion();
    }

    function $_isInitializing() external view returns (bool ret0) {
        (ret0) = super._isInitializing();
    }

    function $_getImplementation() external view returns (address ret0) {
        (ret0) = super._getImplementation();
    }

    function $_upgradeTo(address newImplementation) external {
        super._upgradeTo(newImplementation);
    }

    function $_upgradeToAndCall(address newImplementation,bytes calldata data,bool forceCall) external {
        super._upgradeToAndCall(newImplementation,data,forceCall);
    }

    function $_upgradeToAndCallUUPS(address newImplementation,bytes calldata data,bool forceCall) external {
        super._upgradeToAndCallUUPS(newImplementation,data,forceCall);
    }

    function $_getAdmin() external view returns (address ret0) {
        (ret0) = super._getAdmin();
    }

    function $_changeAdmin(address newAdmin) external {
        super._changeAdmin(newAdmin);
    }

    function $_getBeacon() external view returns (address ret0) {
        (ret0) = super._getBeacon();
    }

    function $_upgradeBeaconToAndCall(address newBeacon,bytes calldata data,bool forceCall) external {
        super._upgradeBeaconToAndCall(newBeacon,data,forceCall);
    }

    function $_requireFromEntryPoint() external view {
        super._requireFromEntryPoint();
    }

    function $_validateNonce(uint256 nonce) external view {
        super._validateNonce(nonce);
    }

    function $_payPrefund(uint256 missingAccountFunds) external {
        super._payPrefund(missingAccountFunds);
    }
}

