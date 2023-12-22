// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./DataLib.sol";
import "./IFunWallet.sol";
import "./IValidation.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

abstract contract WalletModules {
	using SafeERC20 for IERC20;
	mapping(uint32 => uint224) public permitNonces;
	uint256[50] private __gap;

	bytes32 public constant salt = keccak256("Create3Deployer.deployers()");
	bytes32 public constant EIP712_DOMAIN =
		keccak256(abi.encode("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"));
	string public constant PERMIT_TYPEHASH = "PermitTransferStruct(address token,address to,uint256 amount,uint256 nonce)";

	/**
	 * @notice generates correct hash for signature.
	 * @param token token to transfer.
	 * @param to address to transfer tokens to.
	 * @param amount amount of tokens to transfer.
	 * @param nonce nonce to check against signature data with.
	 * @return _hash hash of permit data.
	 */

	function getPermitHash(address token, address to, uint256 amount, uint256 nonce) public view returns (bytes32) {
		bytes32 DOMAIN_SEPARATOR = keccak256(abi.encode(EIP712_DOMAIN, salt, keccak256("1"), block.chainid, address(this), salt));
		return keccak256(abi.encodePacked(DOMAIN_SEPARATOR, keccak256(abi.encode(PERMIT_TYPEHASH, token, to, amount, nonce))));
	}

	/**
	 * @notice gets nonce for a key.
	 * @param key base of nonce.
	 */
	function getNonce(uint32 key) external view returns (uint256 out) {
		out = (uint256(key) << 224) | permitNonces[key];
	}

	/**
	 * @notice Validates and executes permit based transfer.
	 * @param token token to transfer.
	 * @param to address to transfer tokens to.
	 * @param amount amount of tokens to transfer.
	 * @param nonce nonce to check against signature data with.
	 * @param sig signature of permit hash.
	 * @return true if transfer was successful
	 */
	function permitTransfer(address token, address to, uint256 amount, uint256 nonce, bytes calldata sig) external returns (bool) {
		uint256 sigTimeRange = validatePermit(token, to, amount, nonce, sig);
		ValidationData memory data = DataLib.parseValidationData(sigTimeRange);
		bool validPermitSignature = sigTimeRange == 0 ||
			(uint160(sigTimeRange) == 0 && (block.timestamp <= data.validUntil && block.timestamp >= data.validAfter));
		require(validPermitSignature, "FW523");

		++permitNonces[uint32(nonce >> 224)];
		try IFunWallet(address(this)).transferErc20(token, to, amount) {
			return true;
		} catch Error(string memory out) {
			revert(string.concat("FW701: ", out));
		}
	}

	/**
	 * @notice Validates permit based transfer.
	 * @param token token to transfer.
	 * @param to address to transfer tokens to.
	 * @param amount amount of tokens to transfer.
	 * @param nonce nonce to check against signature data with.
	 * @param sig signature of permit hash.
	 */
	function validatePermit(address token, address to, uint256 amount, uint256 nonce, bytes calldata sig) public view returns (uint256) {
		bytes32 _hash = getPermitHash(token, to, amount, nonce);
		/** 
			since validatePermit and permitTransfer have the same parameters we replace the selector of the call to validate
			to get the calldata for permitTransfer 
		 */
		bytes memory data = msg.data;
		for (uint256 i = 0; i < 4; ++i) {
			data[i] = this.permitTransfer.selector[i];
		}
		require(permitNonces[uint32(nonce >> 224)] == uint224(nonce), "FW700");
		return IValidation(address(this)).isValidAction(address(this), 0, data, sig, _hash);
	}
}

