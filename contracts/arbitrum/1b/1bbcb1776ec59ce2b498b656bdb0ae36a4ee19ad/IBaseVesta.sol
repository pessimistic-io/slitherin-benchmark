// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

interface IBaseVesta {
	error NonReentrancy();
	error InvalidPermission();
	error InvalidAddress();
	error CannotBeNativeChainToken();
	error InvalidContract();
	error NumberIsZero();
	error SanitizeMsgValueFailed(
		address _token,
		uint256 _paramValue,
		uint256 _msgValue
	);

	event PermissionChanged(address indexed _address, bytes1 newPermission);

	/** 
	@notice setPermission to an address so they have access to specific functions.
	@dev can add multiple permission by using | between them
	@param _address the address that will receive the permissions
	@param _permission the bytes permission(s)
	*/
	function setPermission(address _address, bytes1 _permission) external;

	/** 
	@notice get the permission level on an address
	@param _address the address you want to check the permission on
	@return accessLevel the bytes code of the address permission
	*/
	function getPermissionLevel(address _address) external view returns (bytes1);

	/** 
	@notice Verify if an address has specific permissions
	@param _address the address you want to check
	@param _accessLevel the access level you want to verify on
	@return hasAccess return true if the address has access
	*/
	function hasPermissionLevel(address _address, bytes1 _accessLevel)
		external
		view
		returns (bool);
}

