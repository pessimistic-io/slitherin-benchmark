// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { ERC20 } from "./ERC20.sol";
import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { FixedPointMathLib } from "./FixedPointMathLib.sol";
import { IERC4626 } from "./IERC4626.sol";
import { Accounting } from "./Accounting.sol";
import { SafeCast } from "./SafeCast.sol";
import { Auth, AuthConfig } from "./Auth.sol";
import { Fees, FeeConfig } from "./Fees.sol";

/// @notice Minimal ERC4626 tokenized Vault implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/mixins/ERC4626.sol)
abstract contract ERC4626 is Auth, Accounting, Fees, IERC4626, ERC20 {
	using SafeERC20 for ERC20;
	using FixedPointMathLib for uint256;

	/*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

	// locked liquidity to prevent rounding errors
	uint256 public constant MIN_LIQUIDITY = 1e3;

	/*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

	ERC20 immutable asset;

	constructor(
		ERC20 _asset,
		string memory _name,
		string memory _symbol
	) ERC20(_name, _symbol) {
		asset = _asset;
	}

	function decimals() public view override returns (uint8) {
		return asset.decimals();
	}

	function totalAssets() public view virtual override returns (uint256) {
		return asset.balanceOf(address(this));
	}

	/*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

	function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
		// This check is no longer necessary because we use MIN_LIQUIDITY
		// Check for rounding error since we round down in previewDeposit.
		// require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");
		shares = previewDeposit(assets);

		// Need to transfer before minting or ERC777s could reenter.
		asset.safeTransferFrom(msg.sender, address(this), assets);

		// lock minimum liquidity if totalSupply is 0
		if (totalSupply() == 0) {
			if (MIN_LIQUIDITY > shares) revert MinLiquidity();
			shares -= MIN_LIQUIDITY;
			_mint(address(1), MIN_LIQUIDITY);
		}

		_mint(receiver, shares);

		emit Deposit(msg.sender, receiver, assets, shares);

		afterDeposit(assets, shares);
	}

	function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
		assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

		// Need to transfer before minting or ERC777s could reenter.
		asset.safeTransferFrom(msg.sender, address(this), assets);

		_mint(receiver, shares);

		emit Deposit(msg.sender, receiver, assets, shares);

		afterDeposit(assets, shares);
	}

	function withdraw(
		uint256 assets,
		address receiver,
		address owner
	) public virtual returns (uint256 shares) {
		shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

		// if not owner, allowance must be enforced
		if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);

		beforeWithdraw(assets, shares);

		_burn(owner, shares);

		emit Withdraw(msg.sender, receiver, owner, assets, shares);

		asset.safeTransfer(receiver, assets);
	}

	function redeem(
		uint256 shares,
		address receiver,
		address owner
	) public virtual returns (uint256 assets) {
		// if not owner, allowance must be enforced
		if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);

		// This check is no longer necessary because we use MIN_LIQUIDITY
		// Check for rounding error since we round down in previewRedeem.
		// require((assets = previewRedeem(shares)) != 0, "ZEROassetS");
		assets = previewRedeem(shares);

		beforeWithdraw(assets, shares);

		_burn(owner, shares);

		emit Withdraw(msg.sender, receiver, owner, assets, shares);

		asset.safeTransfer(receiver, assets);
	}

	/*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

	function maxDeposit(address) public view virtual returns (uint256) {
		return type(uint256).max;
	}

	function maxMint(address) public view virtual returns (uint256) {
		return type(uint256).max;
	}

	function maxWithdraw(address owner) public view virtual returns (uint256) {
		return convertToAssets(balanceOf(owner));
	}

	function maxRedeem(address owner) public view virtual returns (uint256) {
		return balanceOf(owner);
	}

	/*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

	function beforeWithdraw(uint256 assets, uint256 shares) internal virtual {}

	function afterDeposit(uint256 assets, uint256 shares) internal virtual {}

	// OVERRIDES
	function totalSupply() public view override(Accounting, ERC20) returns (uint256) {
		return ERC20.totalSupply();
	}

	error MinLiquidity();
}

