// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "./ERC20.sol";
import { ISuperComposableYield } from "./ISuperComposableYield.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { IERC20MetadataUpgradeable as IERC20Metadata } from "./IERC20MetadataUpgradeable.sol";
import { Accounting } from "./Accounting.sol";
import { ERC20Permit, EIP712 } from "./draft-ERC20Permit.sol";

// import "hardhat/console.sol";

abstract contract SCYBase is
	ISuperComposableYield,
	ReentrancyGuard,
	ERC20,
	Accounting,
	ERC20Permit
{
	using SafeERC20 for IERC20;

	address internal constant NATIVE = address(0);
	uint256 internal constant ONE = 1e18;
	uint256 public constant MIN_LIQUIDITY = 1e3;

	// solhint-disable no-empty-blocks
	receive() external payable {}

	constructor(string memory _name, string memory _symbol)
		ERC20(_name, _symbol)
		ERC20Permit(_name)
	{}

	/*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

	/**
	 * @dev See {ISuperComposableYield-deposit}
	 */
	function deposit(
		address receiver,
		address tokenIn,
		uint256 amountTokenToPull,
		uint256 minSharesOut
	) external payable nonReentrant returns (uint256 amountSharesOut) {
		require(isValidBaseToken(tokenIn), "SCY: Invalid tokenIn");

		if (tokenIn == NATIVE && amountTokenToPull != 0) revert CantPullEth();
		else if (amountTokenToPull != 0) _transferIn(tokenIn, msg.sender, amountTokenToPull);

		// this depends on strategy
		// this supports depositing directly into strategy to save gas
		uint256 amountIn = getFloatingAmount(tokenIn);
		if (amountIn == 0) revert ZeroAmount();

		amountSharesOut = _deposit(receiver, tokenIn, amountIn);
		if (amountSharesOut < minSharesOut) revert InsufficientOut(amountSharesOut, minSharesOut);

		// lock minimum liquidity if totalSupply is 0
		if (totalSupply() == 0) {
			if (MIN_LIQUIDITY > amountSharesOut) revert MinLiquidity();
			amountSharesOut -= MIN_LIQUIDITY;
			_mint(address(1), MIN_LIQUIDITY);
		}

		_mint(receiver, amountSharesOut);
		emit Deposit(msg.sender, receiver, tokenIn, amountIn, amountSharesOut);
	}

	/**
	 * @dev See {ISuperComposableYield-redeem}
	 */
	function redeem(
		address receiver,
		uint256 amountSharesToRedeem,
		address tokenOut,
		uint256 minTokenOut
	) external nonReentrant returns (uint256 amountTokenOut) {
		require(isValidBaseToken(tokenOut), "SCY: invalid tokenOut");

		// this is to handle a case where the strategy sends funds directly to user
		uint256 amountToTransfer;
		(amountTokenOut, amountToTransfer) = _redeem(receiver, tokenOut, amountSharesToRedeem);
		if (amountTokenOut < minTokenOut) revert InsufficientOut(amountTokenOut, minTokenOut);

		if (amountToTransfer > 0) _transferOut(tokenOut, receiver, amountToTransfer);

		emit Redeem(msg.sender, receiver, tokenOut, amountSharesToRedeem, amountTokenOut);
	}

	/**
	 * @notice mint shares based on the deposited base tokens
	 * @param tokenIn base token address used to mint shares
	 * @param amountDeposited amount of base tokens deposited
	 * @return amountSharesOut amount of shares minted
	 */
	function _deposit(
		address receiver,
		address tokenIn,
		uint256 amountDeposited
	) internal virtual returns (uint256 amountSharesOut);

	/**
	 * @notice redeems base tokens based on amount of shares to be burned
	 * @param tokenOut address of the base token to be redeemed
	 * @param amountSharesToRedeem amount of shares to be burned
	 * @return amountTokenOut amount of base tokens redeemed
	 */
	function _redeem(
		address receiver,
		address tokenOut,
		uint256 amountSharesToRedeem
	) internal virtual returns (uint256 amountTokenOut, uint256 tokensToTransfer);

	/*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

	/**
	 * @dev See {ISuperComposableYield-exchangeRateCurrent}
	 */
	function exchangeRateCurrent() external virtual override returns (uint256 res);

	/**
	 * @dev See {ISuperComposableYield-exchangeRateStored}
	 */
	function exchangeRateStored() external view virtual override returns (uint256 res);

	// VIRTUALS
	function getFloatingAmount(address token) public view virtual returns (uint256);

	/**
	 * @notice See {ISuperComposableYield-getBaseTokens}
	 */
	function getBaseTokens() external view virtual override returns (address[] memory res);

	/**
	 * @dev See {ISuperComposableYield-isValidBaseToken}
	 */
	function isValidBaseToken(address token) public view virtual override returns (bool);

	function _transferIn(
		address token,
		address to,
		uint256 amount
	) internal virtual;

	function _transferOut(
		address token,
		address to,
		uint256 amount
	) internal virtual;

	function _selfBalance(address token) internal view virtual returns (uint256);

	function _depositNative() internal virtual;

	// OVERRIDES
	function totalSupply() public view virtual override(ERC20, IERC20) returns (uint256) {
		return ERC20.totalSupply();
	}

	function sendERC20ToStrategy() public view virtual returns (bool) {
		return false;
	}

	error CantPullEth();
	error MinLiquidity();
	error InsufficientOut(uint256 amountOut, uint256 minOut);
}

