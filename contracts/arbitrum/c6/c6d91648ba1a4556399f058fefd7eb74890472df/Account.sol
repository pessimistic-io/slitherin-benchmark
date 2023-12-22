// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

import "./ECDSA.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

import "./BaseAccount.sol";
import "./TokenCallbackHandler.sol";

import "./ISingleton.sol";

/**
 * @title Account
 * @dev A minimal account that has execute and Ether handling methods. It has a single signer (owner) that can send requests through the entryPoint.
 */
contract Account is BaseAccount, TokenCallbackHandler, UUPSUpgradeable, Initializable {
  using ECDSA for bytes32;

  address public owner;
  address public relayer;

  IEntryPoint private immutable _entryPoint;
  ISingleton private immutable _singleton;

  event AccountInitialized(IEntryPoint indexed entryPoint, address indexed owner);

  modifier onlyOwner() {
    _onlyOwner();
    _;
  }

  /// @inheritdoc BaseAccount
  function entryPoint() public view virtual override returns (IEntryPoint) {
    return _entryPoint;
  }

  // Fallback function to accept Ether
  receive() external payable {}

  /**
   * @dev Constructor to initialize the contract.
   * @param anEntryPoint Address of the entry point.
   * @param aSingleton Address of the singleton contract.
   */
  constructor(IEntryPoint anEntryPoint, ISingleton aSingleton) {
    _entryPoint = anEntryPoint;
    _singleton = aSingleton;
    _disableInitializers();
  }

  /**
   * @dev Modifier to check if the caller is the owner.
   */
  function _onlyOwner() internal view {
    require(msg.sender == owner || msg.sender == address(this), "only owner");
  }

  /**
   * @dev Execute a transaction (called directly from owner or by entryPoint).
   * @param dest Address of the destination contract.
   * @param value Ether value to send with the transaction.
   * @param func Data for the function call.
   */
  function execute(address dest, uint256 value, bytes calldata func) external {
    _requireFromEntryPointOrOwner();
    _call(dest, value, func);
  }

  /**
   * @dev Execute a sequence of transactions.
   * @param dest Array of destination addresses.
   * @param value Array of Ether values to send with the transactions.
   * @param func Array of data for the function calls.
   */
  function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func) external {
    _requireFromEntryPointOrOwner();
    require(dest.length == func.length && (value.length == 0 || value.length == func.length), "wrong array lengths");
    executeBatchLogic(dest, value, func);
  }

  /**
   * @dev Execute a batch of transactions with a guard's validation data.
   * @param dest Array of destination addresses.
   * @param value Array of Ether values to send with the transactions.
   * @param func Array of data for the function calls.
   * @param validationData Validation data signed by the owner or relayer.
   */
  function executeBatchWithGuard(
    address[] calldata dest,
    uint256[] calldata value,
    bytes[] calldata func,
    bytes calldata validationData
  ) external {
    _singleton.guardValidate(dest, value, func, validationData, owner);
    executeBatchLogic(dest, value, func);
  }

  /**
   * @dev Internal function to execute a batch of transactions.
   * @param dest Array of destination addresses.
   * @param value Array of Ether values to send with the transactions.
   * @param func Array of data for the function calls.
   */
  function executeBatchLogic(address[] calldata dest, uint256[] calldata value, bytes[] calldata func) internal {
    if (value.length == 0) {
      for (uint256 i = 0; i < dest.length; i++) {
        _call(dest[i], 0, func[i]);
      }
    } else {
      for (uint256 i = 0; i < dest.length; i++) {
        _call(dest[i], value[i], func[i]);
      }
    }
  }

  /**
   * @dev Initialize the account with an owner and a relayer.
   * @param anOwner Address of the owner.
   * @param aRelayer Address of the relayer.
   */
  function initialize(address anOwner, address aRelayer) public virtual initializer {
    _initialize(anOwner, aRelayer);
  }

  /**
   * @dev Internal function to initialize the account.
   * @param anOwner Address of the owner.
   * @param aRelayer Address of the relayer.
   */
  function _initialize(address anOwner, address aRelayer) internal virtual {
    owner = anOwner;
    relayer = aRelayer;
    emit AccountInitialized(_entryPoint, owner);
  }

  /**
   * @dev Modifier to require the function call to come from the entryPoint or owner.
   */
  function _requireFromEntryPointOrOwner() internal view {
    require(msg.sender == address(entryPoint()) || msg.sender == owner, "account: not Owner or EntryPoint");
  }

  /**
   * @inheritdoc BaseAccount
   * @dev Validate the user operation's signature.
   */
  function _validateSignature(
    UserOperation calldata userOp,
    bytes32 userOpHash
  ) internal virtual override returns (uint256 validationData) {
    bytes32 hash = userOpHash.toEthSignedMessageHash();
    address recoveredAddress = hash.recover(userOp.signature);
    uint256 result = 0;

    // Check the signature of the owner
    if (owner != recoveredAddress && relayer != recoveredAddress) {
      result = SIG_VALIDATION_FAILED;
    }

    return result;
  }

  /**
   * @dev Internal function to perform an external call.
   */
  function _call(address target, uint256 value, bytes memory data) internal {
    (bool success, bytes memory result) = target.call{ value: value }(data);
    if (!success) {
      assembly {
        revert(add(result, 32), mload(result))
      }
    }
  }

  /**
   * @dev Check the current account deposit in the entryPoint.
   * @return The current account deposit.
   */
  function getDeposit() public view returns (uint256) {
    return entryPoint().balanceOf(address(this));
  }

  /**
   * @dev Deposit more funds for this account in the entryPoint.
   */
  function addDeposit() public payable {
    entryPoint().depositTo{ value: msg.value }(address(this));
  }

  /**
   * @dev Withdraw value from the account's deposit to a specified address.
   * @param withdrawAddress Address to send the withdrawn Ether to.
   * @param amount Amount to withdraw.
   */
  function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlyOwner {
    entryPoint().withdrawTo(withdrawAddress, amount);
  }

  /**
   * @inheritdoc UUPSUpgradeable
   * @dev Authorize an upgrade by checking that only the owner can trigger it.
   * @param newImplementation Address of the new implementation.
   */
  function _authorizeUpgrade(address newImplementation) internal view override {
    (newImplementation);
    _onlyOwner();
  }

  /**
   * @dev Change the relayer address.
   * @param newRelayer The new address of the relayer.
   */
  function changeRelayer(address newRelayer) external onlyOwner {
    relayer = newRelayer;
  }
}

