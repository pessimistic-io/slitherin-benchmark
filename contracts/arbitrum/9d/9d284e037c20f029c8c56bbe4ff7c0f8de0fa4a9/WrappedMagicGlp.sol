pragma solidity 0.8.17;

// SPDX-License-Identifier: MIT

import "./ERC20.sol";
import "./IERC4626.sol";
import "./IGlpManager.sol";
import "./IGlpRewardRouter.sol";


contract WrappedMagicGlp is ERC20
{
	ERC20 public asset;
	IERC4626 public magicGlp;

	event Withdrawed(uint256 shares, uint256 withdrawn, address receiver);
	event Deposited(uint256 amount, uint256 shares, address user);

	constructor(ERC20 _asset,
		IERC4626 _magicGlp) ERC20("WrappedMagicGLP", "wMagicGLP")
	{
		asset = _asset;
		magicGlp = _magicGlp;

		asset.approve(address(magicGlp), type(uint256).max);
	}

	function exchangeRateCurrent() public returns (uint256) 
	{
		return magicGlp.convertToAssets(10**18);
	}

	/// @param amount - amount of asset.
	/// @return shares - amount of yTokens.
	function mint(uint256 amount) public returns (uint256 shares)
	{
		asset.transferFrom(msg.sender, address(this), amount);

		shares = magicGlp.deposit(amount, address(this));

		_mint(msg.sender, shares);

		emit Deposited(amount, shares, msg.sender);

		return 0;
	}

	/// @param shares - amount of yTokens
	/// @return withdrawn - amount of asset.
	function redeem(uint256 shares) public returns (uint256 withdrawn)
	{
		if (shares > 0)
		{
			withdrawn = magicGlp.redeem(shares, address(this), address(this));

			_burn(msg.sender, shares);

			asset.transfer(msg.sender, withdrawn);
		}
		else
		{
			withdrawn = 0;
		}

		emit Withdrawed(shares, withdrawn, msg.sender);

		return 0;
	}

	function decimals() public view virtual override returns (uint8)
	{
        return 18;
    }
}

