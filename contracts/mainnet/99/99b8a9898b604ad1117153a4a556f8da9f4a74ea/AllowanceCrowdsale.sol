// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Math.sol";
import "./Crowdsale.sol";

/**
 * @title AllowanceCrowdsale
 * @dev Borrow from https://github.dev/OpenZeppelin/openzeppelin-contracts/blob/docs-v2.x/contracts/crowdsale/emission/AllowanceCrowdsale.sol
 * @dev Extension of Crowdsale where tokens are held by a wallet, which approves an allowance to the crowdsale.
 */
abstract contract AllowanceCrowdsale is Crowdsale {
	using SafeERC20 for IERC20;

	address public _tokenWallet;

	/**
	 * @dev Constructor, takes token wallet address.
	 * @param tokenWallet Address holding the tokens, which has approved allowance to the crowdsale.
	 */
	constructor(address tokenWallet) {
		require(
			tokenWallet != address(0),
			"AllowanceCrowdsale: token wallet is the zero address"
		);
		_tokenWallet = tokenWallet;
	}
	
	/**
	 * @dev Checks the amount of tokens left in the allowance.
	 * @return Amount of tokens left in the allowance
	 */
	function remainingTokens() public view returns (uint256) {
		return
			Math.min(
				_token.balanceOf(_tokenWallet),
				_token.allowance(_tokenWallet, address(this))
			);
	}

	/**
	 * @dev Overrides parent behavior by transferring tokens from wallet.
	 * @param beneficiary Token purchaser
	 * @param tokenAmount Amount of tokens purchased
	 */
	function _deliverTokens(address beneficiary, uint256 tokenAmount)
		internal
		virtual
		override
	{
		_token.safeTransferFrom(_tokenWallet, beneficiary, tokenAmount);
	}
}

