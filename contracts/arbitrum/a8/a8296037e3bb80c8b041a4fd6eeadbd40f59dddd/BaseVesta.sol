// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./IBaseVesta.sol";

import "./OwnableUpgradeable.sol";

/**
@title BaseVesta
@notice Inherited by most of our contracts. It has a permission system & reentrency protection inside it.
@dev Binary Roles Recommended Slots
0x01  |  0x10
0x02  |  0x20
0x04  |  0x40
0x08  |  0x80

Don't use other slots unless you are familiar with bitewise operations
*/

abstract contract BaseVesta is IBaseVesta, OwnableUpgradeable {
	address internal constant RESERVED_ETH_ADDRESS = address(0);
	uint256 internal constant MAX_UINT256 = type(uint256).max;

	address internal SELF;
	bool private reentrencyStatus;

	mapping(address => bytes1) internal permissions;

	uint256[49] private __gap;

	modifier onlyContract(address _address) {
		if (_address.code.length == 0) revert InvalidContract();
		_;
	}

	modifier onlyContracts(address _address, address _address2) {
		if (_address.code.length == 0 || _address2.code.length == 0) {
			revert InvalidContract();
		}
		_;
	}

	modifier onlyValidAddress(address _address) {
		if (_address == address(0)) {
			revert InvalidAddress();
		}

		_;
	}

	modifier nonReentrant() {
		if (reentrencyStatus) revert NonReentrancy();
		reentrencyStatus = true;
		_;
		reentrencyStatus = false;
	}

	modifier hasPermission(bytes1 access) {
		if (permissions[msg.sender] & access == 0) revert InvalidPermission();
		_;
	}

	modifier hasPermissionOrOwner(bytes1 access) {
		if (permissions[msg.sender] & access == 0 && msg.sender != owner()) {
			revert InvalidPermission();
		}

		_;
	}

	modifier notZero(uint256 _amount) {
		if (_amount == 0) revert NumberIsZero();
		_;
	}

	function __BASE_VESTA_INIT() internal onlyInitializing {
		SELF = address(this);
		__Ownable_init();
	}

	function setPermission(address _address, bytes1 _permission)
		external
		override
		onlyOwner
	{
		_setPermission(_address, _permission);
	}

	function _clearPermission(address _address) internal virtual {
		_setPermission(_address, 0x00);
	}

	function _setPermission(address _address, bytes1 _permission) internal virtual {
		permissions[_address] = _permission;
		emit PermissionChanged(_address, _permission);
	}

	function getPermissionLevel(address _address)
		external
		view
		override
		returns (bytes1)
	{
		return permissions[_address];
	}

	function hasPermissionLevel(address _address, bytes1 accessLevel)
		public
		view
		override
		returns (bool)
	{
		return permissions[_address] & accessLevel != 0;
	}

	/** 
	@notice _sanitizeMsgValueWithParam is for multi-token payable function.
	@dev msg.value should be set to zero if the token used isn't a native token.
		address(0) is reserved for Native Chain Token.
		if fails, it will reverts with SanitizeMsgValueFailed(address _token, uint256 _paramValue, uint256 _msgValue).
	@return sanitizeValue which is the sanitize value you should use in your code.
	*/
	function _sanitizeMsgValueWithParam(address _token, uint256 _paramValue)
		internal
		view
		returns (uint256)
	{
		if (RESERVED_ETH_ADDRESS == _token) {
			return msg.value;
		} else if (msg.value == 0) {
			return _paramValue;
		}

		revert SanitizeMsgValueFailed(_token, _paramValue, msg.value);
	}

	function isContract(address _address) internal view returns (bool) {
		return _address.code.length > 0;
	}
}


