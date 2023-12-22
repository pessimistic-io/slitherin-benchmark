// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./IAccount.sol";
import "./IFunWallet.sol";
import "./IModule.sol";
import "./IFunWalletFactory.sol";

import "./TokenCallbackHandler.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

import "./WalletState.sol";
import "./WalletModules.sol";
import "./WalletFee.sol";
import "./WalletValidation.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";

/**
 * @title FunWallet Contract
 * @dev This contract implements the `IFunWallet` interface, and it is upgradeable using the `UUPSUpgradeable` contract.
 */
contract FunWallet is
	IFunWallet,
	IAccount,
	Initializable,
	UUPSUpgradeable,
	TokenCallbackHandler,
	WalletState,
	WalletFee,
	WalletModules,
	WalletValidation
{
	using SafeERC20 for IERC20;
	/// @dev This constant is used to define the version of this contract.
	uint256 public constant VERSION = 1;

	IFunWalletFactory public factory;
	uint256[50] private __gap;

	constructor() {
		_disableInitializers();
	}

	function initialize(IEntryPoint _newEntryPoint, bytes calldata validationInitData) public initializer {
		require(address(_newEntryPoint) != address(0), "FW500");
		require(msg.sender != address(this), "FW501");
		factory = IFunWalletFactory(msg.sender);
		_entryPoint = _newEntryPoint;
		initValidations(validationInitData);
		emit EntryPointChanged(address(_newEntryPoint));
	}

	/**
	 * @notice Transfer ERC20 tokens from the wallet to a destination address.
	 * @param token ERC20 token address
	 * @param dest Destination address
	 * @param amount Amount of tokens to transfer
	 */
	function transferErc20(address token, address dest, uint256 amount) external {
		_requireFromFunWalletProxy();
		IERC20(token).safeTransfer(dest, amount);
		emit TransferERC20(token, dest, amount);
	}

	/**
	 * @dev Validate user's signature, nonce, and permission.
	 * @param userOp The user operation
	 * @param userOpHash The hash of the user operation
	 * @param missingAccountFunds The amount of missing funds that need to be prefunded to the wallet.
	 * @return sigTimeRange The signature time range for the operation.
	 */
	function validateUserOp(
		UserOperation calldata userOp,
		bytes32 userOpHash,
		uint256 missingAccountFunds
	) external override returns (uint256 sigTimeRange) {
		_requireFromEntryPoint();
		sigTimeRange = _validateUserOp(userOp, userOpHash);
		_payPrefund(missingAccountFunds);
		emit UserOpValidated(userOpHash, userOp, sigTimeRange, missingAccountFunds);
	}

	/**
	 * @notice Validates the user's signature,  and permission for an action.
	 * @param target The address of the contract being called.
	 * @param value The value being transferred in the action.
	 * @param data The calldata for the action.
	 * @param signature The user's signature for the action.
	 * @param _hash The hash of the user operation.
	 * @return out A boolean indicating whether the action is valid.
	 */
	function isValidAction(
		address target,
		uint256 value,
		bytes memory data,
		bytes memory signature,
		bytes32 _hash
	) external view override returns (uint256 out) {
		out = _isValidAction(target, value, data, signature, _hash);
	}

	/**
	 * @notice Update the entry point for this contract
	 * @param _newEntryPoint The address of the new entry point.
	 */
	function updateEntryPoint(IEntryPoint _newEntryPoint) external override {
		_requireFromFunWalletProxy();
		require(address(_newEntryPoint) != address(0), "FW503");
		_entryPoint = _newEntryPoint;
		emit EntryPointChanged(address(_newEntryPoint));
	}

	/**
	 * @notice deposit to entrypoint to prefund the execution.
	 * @dev This function can only be called by the owner of the contract.
	 * @param amount the amount to deposit.
	 */
	function depositToEntryPoint(uint256 amount) external override {
		_requireFromFunWalletProxy();
		require(address(this).balance >= amount, "FW504");
		_entryPoint.depositTo{value: amount}(address(this));
		emit DepositToEntryPoint(amount);
	}

	/**
	 * @notice withdraw deposit from entrypoint
	 * @dev This function can only be called by the owner of the contract.
	 * @param withdrawAddress the address to withdraw Eth to
	 * @param amount the amount to be withdrawn
	 */
	function withdrawFromEntryPoint(address payable withdrawAddress, uint256 amount) external override {
		_requireFromFunWalletProxy();
		_transferEthFromEntrypoint(withdrawAddress, amount);
		emit WithdrawFromEntryPoint(withdrawAddress, amount);
	}

	function _transferEthFromEntrypoint(address payable recipient, uint256 amount) internal override {
		try _entryPoint.withdrawTo(recipient, amount) {} catch Error(string memory revertReason) {
			revert(string.concat("FW505: ", revertReason));
		} catch {
			revert("FW505");
		}
	}

	/**
	 * sends to the entrypoint (msg.sender) the missing funds for this transaction.
	 * subclass MAY override this method for better funds management
	 * (e.g. send to the entryPoint more than the minimum required, so that in future transactions
	 * it will not be required to send again)
	 * @param missingAccountFunds the minimum value this method should send the entrypoint.
	 *  this value MAY be zero, in case there is enough deposit, or the userOp has a paymaster.
	 */
	function _payPrefund(uint256 missingAccountFunds) internal {
		if (missingAccountFunds != 0) {
			(bool success, ) = payable(msg.sender).call{value: missingAccountFunds, gas: type(uint256).max}("");
			(success);
			//ignore failure (its EntryPoint's job to verify, not account.)
		}
	}

	// Checks if module calling wallet was deployed from the same base create3deployer
	function _requireFromModule() internal override {
		bool storedKey;
		bytes32 senderBytes = bytes32(uint256(uint160(msg.sender)));
		bytes32 moduleWhitelistKey = HashLib.hash1(senderBytes);
		assembly {
			storedKey := sload(moduleWhitelistKey)
		}
		if (storedKey) return;
		bytes32 key = IModule(msg.sender).moduleId();
		require(factory.verifyDeployedFrom(key, msg.sender), "FW506");
		assembly {
			sstore(moduleWhitelistKey, 0x01)
		}
	}

	function setState(bytes32 key, bytes calldata val) public override {
		_requireFromModule();
		_setState(key, val);
	}

	function setState32(bytes32 key, bytes32 val) public override {
		_requireFromModule();
		_setState32(key, val);
	}

	function _requireFromFunWalletProxy() internal view {
		require(msg.sender == address(this), "FW502");
	}

	function _requireFromEntryPoint() internal view override(WalletExec, WalletValidation) {
		require(msg.sender == address(_entryPoint), "FW507");
	}

	function _getOracle() internal view override returns (address payable) {
		return factory.getFeeOracle();
	}

	/**
	 * builtin method to support UUPS upgradability
	 */
	function _authorizeUpgrade(address) internal view override {
		require(msg.sender == address(this), "FW502");
	}

	/**
	 * @notice Get the entry point for this contract
	 * @dev This function returns the contract's entry point interface.
	 * @return The contract's entry point interface.
	 */
	function entryPoint() external view override returns (IEntryPoint) {
		return _entryPoint;
	}

	receive() external payable {}

	event TransferERC20(address indexed token, address indexed dest, uint256 amount);
	event DepositToEntryPoint(uint256 amount);
	event UserOpValidated(bytes32 indexed userOpHash, UserOperation userOp, uint256 sigTimeRange, uint256 missingAccountFunds);
	event WithdrawFromEntryPoint(address indexed withdrawAddress, uint256 amount);
}

