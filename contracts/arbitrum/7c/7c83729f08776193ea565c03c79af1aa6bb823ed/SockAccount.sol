// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */
import "./ECDSA.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

import "./BaseAccount.sol";
import "./TokenCallbackHandler.sol";

import "./ISockFunctionRegistry.sol";
import "./SockUserPermissions.sol";
import "./SockOwnable.sol";

/**
 * @title SockAccount
 * @dev SockAccount is an ERC4337 compliant implementation by Sock.
 */
contract SockAccount is
    Initializable,
    BaseAccount,
    TokenCallbackHandler,
    UUPSUpgradeable,
    SockOwnable,
    SockUserPermissions
{
    using ECDSA for bytes32;

    IEntryPoint private immutable _ENTRY_POINT;

    event SockAccountInitialized(
        ISockFunctionRegistry sockFunctionRegistry,
        address indexed owner,
        address indexed sockOwner
    );

    modifier onlyFromEntryPoint() {
        _requireFromEntryPoint();
        _;
    }

    /**
     * @dev Constructor that initializes the EntryPoint
     * @param anEntryPoint address of the entry point
     */
    constructor(IEntryPoint anEntryPoint) {
        _ENTRY_POINT = anEntryPoint;
        _disableInitializers();
    }

    /**
     * @dev public function that initializes the SockAccount
     * @param aSockFunctionRegistry address of the sock function registry
     * @param anOwner address of the owner
     * @param aSockOwner address of the sock owner
     */
    function initialize(
        ISockFunctionRegistry aSockFunctionRegistry,
        address anOwner,
        address aSockOwner
    ) external initializer {
        _initialize(aSockFunctionRegistry, anOwner, aSockOwner);
    }

    // Allows the contract to accept native currency directly
    receive() external payable {}

    /**
     * @dev Execute a transaction. This could be called directly from the owner in event of bundler downtime
     * @param dest target address
     * @param value to send
     * @param func calldata
     */
    function executeOwner(
        address dest,
        uint256 value,
        bytes calldata func
    ) external onlyOwner {
        _call(dest, value, func);
    }

    /**
     * @dev Execute a transaction. This can only be called from the EntryPoint
     * @param dest target address
     * @param value to send
     * @param func calldata
     * @param signature signature of the message
     * access is restricted to the current owner or sock owner or entry point
     */
    function execute(
        address dest,
        uint256 value,
        bytes calldata func,
        bytes memory signature
    ) external onlyFromEntryPoint {
        _onlyAllowedFunctions(dest, value, func, signature);
        _call(dest, value, func);
    }

    /**
     * @dev Execute a batch of transactions. This could be called directly from the owner or the entry point
     * @param dest array of target addresses
     * @param value array of values to send
     * @param func array of function calls
     * @param signature array of signature of the messages
     * access is retricted to the current owner or sock owner or entry point
     */
    function executeBatch(
        address[] calldata dest,
        uint256[] calldata value,
        bytes[] calldata func,
        bytes[] memory signature
    )
        external
        onlyFromEntryPoint
    {
        require(
            func.length == dest.length &&
            signature.length == func.length &&
            (value.length == 0 || func.length == value.length),
            "wrong array size"
        );

        for (uint256 i = 0; i < dest.length; i++) {
            uint256 sendValue = (value.length > 0) ? value[i] : 0;
            _onlyAllowedFunctions(dest[i], sendValue, func[i], signature[i]);

            _call(dest[i], sendValue, func[i]);
        }
    }

    /**
     * @dev function to set the user permission for a given permission index,
     * In place to allow sock to sponsor transaction gas on permission changes.
     * @param permissionIndexs The indexes of the functions in the sock function registry.
     * @param alloweds Whether the functions are allowed or not.
     * @param isPayables Whether the functions are payable or not.
     * @param signature signature of the signed message
     * Logic access is retricted to the current owner via signature validation.
     */
    function setUserPermissionsFromEntryPoint(uint256[] memory permissionIndexs, bool[] memory alloweds, bool[] memory isPayables, bytes memory signature) external onlyFromEntryPoint {
        require (permissionIndexs.length == alloweds.length && permissionIndexs.length == isPayables.length, "Permission indexs, alloweds, and isPayable lengths must match");
        address signer = _recoverSigner(_buildMessage(abi.encode(permissionIndexs, alloweds, isPayables)), signature);
        require(signer == owner(), "only owner");
        for (uint256 i = 0; i < permissionIndexs.length;) {
            _setUserPermission(permissionIndexs[i], alloweds[i], isPayables[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
    * @dev function to transfer ownership of the sock to a new owner
    * @param newSockOwner address of the new owner
    * if the new owner is zero address we also must revoke the registry
    * access is retricted to the current owner or sock owner
    */
    function transferSockOwnership(address newSockOwner) public onlyOwnerOrSockOwner {
        if (newSockOwner == address(0)) {
            _transferSockFunctionRegistry(ISockFunctionRegistry(newSockOwner));
            _transferRecoveryOwnership(newSockOwner);
        }
        _transferSockOwnership(newSockOwner);
    }

    /**
     * @dev function to withdraw value from the account's deposit
     * @param withdrawAddress target to send to
     * @param amount to withdraw
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlyOwner {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    /**
     * @dev function to deposit more funds for this account in the entryPoint
     */
    function addDeposit() public payable {
        entryPoint().depositTo{value : msg.value}(address(this));
    }

    /**
     * @dev function to check the current account deposit in the entryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _ENTRY_POINT;
    }

    /**
     * @dev internal function to make a call to a target contract
     * @param target address of the target contract
     * @param value to send
     * @param data to send
     */
    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value : value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * @dev internal function that initializes the SockAccount
     * @param aSockFunctionRegistry address of the sock function registry
     * @param anOwner address of the owner
     * @param aSockOwner address of the sock owner
     */
    function _initialize(
        ISockFunctionRegistry aSockFunctionRegistry,
        address anOwner,
        address aSockOwner
    ) internal {
        _sockOwner = aSockOwner;
        _owner = anOwner;
        _sockFunctionRegistry = aSockFunctionRegistry;
        _recoveryOwner = anOwner;
        emit SockAccountInitialized(aSockFunctionRegistry, anOwner, aSockOwner);
    }

    /**
     * @dev internal function to enforce function access control
     * @param dest target address
     * @param value to send
     * @param func calldata
     * @param signature signature of the signed message
     */
    function _onlyAllowedFunctions(
        address dest,
        uint256 value,
        bytes calldata func,
        bytes memory signature
    ) internal view {
        address signer = _recoverSigner(_buildMessage(func), signature);
        require(signer == owner() || signer == sockOwner(), "only owner or sock owner");
        if (signer == sockOwner()) {
            _requireOnlyAllowedFunctions(dest, func, value);
        }
    }

    /**
     * @dev internal function to build a message for signing
     * @param data calldata that was signed
     */
    function _buildMessage(
        bytes memory data
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(block.chainid, address(this), data, getNonce()));
    }

    /**
     * @dev internal function to validate a signature from erc4337
     * @param userOp full user operation to validate
     * @param userOpHash hash of the user operation
     */
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
    internal override view returns (uint256 validationData) {
        address signer = _recoverSigner(userOpHash, userOp.signature);
        if (owner() == signer || sockOwner() == signer) { return 0; }
        return SIG_VALIDATION_FAILED;
    }

    /**
     * @dev function to authorize an upgrade of the contract.
     * This is a necessary part of the UUPS upgradability pattern
     * @param newImplementation address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        _checkOwner();
    }

    /**
     * @dev internal function to recover the signer from a signature
     * @param message to recover from
     * @param signature to recover from
     */
    function _recoverSigner(
        bytes32 message,
        bytes memory signature
    ) internal virtual pure returns (address) {
        return message.toEthSignedMessageHash().recover(signature);
    }

}

