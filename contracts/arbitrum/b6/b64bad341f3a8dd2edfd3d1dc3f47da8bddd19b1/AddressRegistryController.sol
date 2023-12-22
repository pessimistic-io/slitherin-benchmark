// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IAddressRegistryV2.sol";

contract AddressRegistryController is Ownable {

    event FunctionOwnershipTransferred(address indexed previousOwner, address indexed newOwner, bytes32 functionId);

    IAddressRegistryV2 public registry;

    bytes32 public constant SET_ADMIN = "SET_ADMIN";
    bytes32 public constant SET_LOCK_MANAGER = "SET_LOCK_MANAGER";
    bytes32 public constant SET_REVEST_TOKEN = "SET_REVEST_TOKEN";
    bytes32 public constant SET_TOKEN_VAULT = "SET_TOKEN_VAULT";
    bytes32 public constant SET_REVEST = "SET_REVEST";
    bytes32 public constant SET_FNFT = "SET_FNFT";
    bytes32 public constant SET_METADATA = "SET_METADATA";
    bytes32 public constant SET_REWARDS_HANDLER = 'SET_REWARDS_HANDLER';
    bytes32 public constant UNPAUSE_TOKEN = 'UNPAUSE_TOKEN';
    bytes32 public constant MODIFY_BREAKER = 'MODIFY_BREAKER';
    bytes32 public constant MODIFY_PAUSER = 'MODIFY_PAUSER';


    mapping(bytes32 => address) public functionOwner;

    constructor(address _provider) Ownable() {
        registry = IAddressRegistryV2(_provider);
        functionOwner[SET_ADMIN] = _msgSender();
        functionOwner[SET_LOCK_MANAGER] = _msgSender();
        functionOwner[SET_REVEST_TOKEN] = _msgSender();
        functionOwner[SET_TOKEN_VAULT] = _msgSender();
        functionOwner[SET_REVEST] = _msgSender();
        functionOwner[SET_FNFT] = _msgSender();
        functionOwner[SET_METADATA] = _msgSender();
        functionOwner[SET_REWARDS_HANDLER] = _msgSender();
        functionOwner[UNPAUSE_TOKEN] = _msgSender();
        functionOwner[MODIFY_BREAKER] = _msgSender();
        functionOwner[MODIFY_PAUSER] = _msgSender();
    }

    modifier onlyFunctionOwner(bytes32 functionId) {
        require(_msgSender() == functionOwner[functionId] && _msgSender() != address(0), 'E079');
        _;
    }

    ///
    /// Controller control functions
    ///

    function transferFunctionOwnership(
        bytes32 functionId, 
        address newFunctionOwner
    ) external onlyFunctionOwner(functionId) {
        address oldFunctionOwner = functionOwner[functionId];
        functionOwner[functionId] = newFunctionOwner;
        emit FunctionOwnershipTransferred(oldFunctionOwner, newFunctionOwner, functionId);
    }

    function renounceFunctionOwnership(
        bytes32 functionId
    ) external onlyFunctionOwner(functionId) {
        address oldFunctionOwner = functionOwner[functionId];
        functionOwner[functionId] = address(0);
        emit FunctionOwnershipTransferred(oldFunctionOwner, address(0), functionId);
    }
    
    ///
    /// Control functions
    ///

    /// Pass through unpause signal to Registry
    function unpauseToken() external onlyFunctionOwner(UNPAUSE_TOKEN) {
        registry.unpauseToken();
    }
    
    /// Admin function for adding or removing breakers
    function modifyBreaker(address breaker, bool grant) external onlyFunctionOwner(MODIFY_BREAKER) {
        registry.modifyBreaker(breaker, grant);
    }

    /// Admin function for adding or removing pausers
    function modifyPauser(address pauser, bool grant) external onlyFunctionOwner(MODIFY_PAUSER) {
        registry.modifyPauser(pauser, grant);
    }


    ///
    /// SETTERS
    ///

    function setAdmin(address admin) external onlyFunctionOwner(SET_ADMIN) {
        registry.setAdmin(admin);
    }

    function setLockManager(address manager) external onlyFunctionOwner(SET_LOCK_MANAGER) {
        registry.setLockManager(manager);
    }

    function setTokenVault(address vault) external onlyFunctionOwner(SET_TOKEN_VAULT) {
        registry.setTokenVault(vault);
    }
   
    function setRevest(address revest) external onlyFunctionOwner(SET_REVEST) {
        registry.setRevest(revest);
    }

    function setRevestFNFT(address fnft) external onlyFunctionOwner(SET_FNFT) {
        registry.setRevestFNFT(fnft);
    }

    function setMetadataHandler(address metadata) external onlyFunctionOwner(SET_METADATA) {
        registry.setMetadataHandler(metadata);
    }

    function setRevestToken(address token) external onlyFunctionOwner(SET_REVEST_TOKEN) {
        registry.setRevestToken(token);
    }

    function setRewardsHandler(address esc) external onlyFunctionOwner(SET_REWARDS_HANDLER) {
        registry.setRewardsHandler(esc);
    }

}

