// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./IStableCoin.sol";

import "./token_ERC20.sol";

/**
@title StableCoin
*/
contract StableCoin is ERC20, IStableCoin {
	address public override owner;

	mapping(address => bool) internal mintBurnAccess;
	mapping(address => bool) internal emergencyStopMintingCollateral;

	modifier hasPermission() {
		if (!mintBurnAccess[msg.sender]) revert NoAccess();
		_;
	}

	modifier onlyOwner() {
		if (owner != msg.sender) revert NotOwner();
		_;
	}

	constructor(address _wallet) ERC20("Vesta Stable", "v-usd") {
		owner = msg.sender;
		mintBurnAccess[_wallet] = true;
	}

	function setOwner(address _newOwner) external override onlyOwner {
		owner = _newOwner;
		emit TransferOwnership(_newOwner);
	}

	function setMintBurnAccess(address _address, bool _status)
		external
		override
		onlyOwner
	{
		mintBurnAccess[_address] = _status;
		emit MintBurnAccessChanged(_address, _status);
	}

	function emergencyStopMinting(address _asset, bool _status)
		external
		override
		onlyOwner
	{
		emergencyStopMintingCollateral[_asset] = _status;
		emit EmergencyStopMintingCollateral(_asset, _status);
	}

	function mintDebt(
		address _asset,
		address _account,
		uint256 _amount
	) external override hasPermission {
		if (emergencyStopMintingCollateral[_asset]) {
			revert MintingBlocked();
		}

		_mint(_account, _amount);
	}

	function mint(address _account, uint256 _amount) external override hasPermission {
		_mint(_account, _amount);
	}

	function burn(address _account, uint256 _amount) external override hasPermission {
		_burn(_account, _amount);
	}

	function isCollateralStopFromMinting(address _token)
		external
		view
		override
		returns (bool)
	{
		return emergencyStopMintingCollateral[_token];
	}

	function hasMintAndBurnPermission(address _address)
		external
		view
		override
		returns (bool)
	{
		return mintBurnAccess[_address];
	}
}

