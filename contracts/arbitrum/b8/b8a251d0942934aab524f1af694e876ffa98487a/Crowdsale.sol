// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Context.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

interface IOracle {
	function usdAmount(uint128 _weiAmount) external view returns (uint256);
}

interface IMintableERC20 is IERC20 {
	function mint(address to, uint256 amount) external;
}

contract Crowdsale is Context, ReentrancyGuard {
	using SafeMath for uint256;
	using SafeERC20 for IMintableERC20;

	// The token being sold
	IMintableERC20 private _token;

	// Address where funds are collected
	address payable private _wallet;

	// Oracle used to calculate usdQuota based on wei amount sent to the contract
	IOracle public oracle;

	// IWO opening date
	uint256 public constant startDate = 1671109200;
	// IWO ending date
	uint256 public constant endDate = 1671548340;

	// _rate is the inverse of the base price.
	// if base price would be 0.05 USD, _rate should be equal to 20.
	uint256 private _rate;

	// Amount of usdc raised
	uint256 private _usdcRaised;

	/**
	 * Event for token purchase logging
	 * @param purchaser who paid for the tokens
	 * @param beneficiary who got the tokens
	 * @param value weis paid for purchase
	 * @param amount amount of tokens purchased
	 */
	event TokensPurchased(
		address indexed purchaser,
		address indexed beneficiary,
		uint256 value,
		uint256 amount
	);

	// tierStep is the amount of USDC needed to jump to the next tier.
	uint256 public constant tierStep = 10000 * 10 ** 6;

	/**
	 * @param __rate Number of token units a buyer gets per wei
	 * @dev The rate is the conversion between wei and the smallest and indivisible
	 * token unit. So, if you are using a rate of 1 with a ERC20Detailed token
	 * with 3 decimals called TOK, 1 wei will give you 1 unit, or 0.001 TOK.
	 * @param __wallet Address where collected funds will be forwarded to
	 * @param __token Address of the token being sold
	 */
	constructor(
		uint256 __rate,
		address payable __wallet,
		IMintableERC20 __token,
		address _oracle
	) {
		require(__rate > 0, "Crowdsale: rate is 0");
		require(
			__wallet != address(0),
			"Crowdsale: wallet is the zero address"
		);
		require(
			address(__token) != address(0),
			"Crowdsale: token is the zero address"
		);
		require(
			address(_oracle) != address(0),
			"Crowdsale: _oracle is the zero address"
		);

		_rate = __rate;
		_wallet = __wallet;
		_token = __token;
		oracle = IOracle(_oracle);
	}

	/**
	 * @dev fallback function ***DO NOT OVERRIDE***
	 * Note that other contracts will transfer funds with a base gas stipend
	 * of 2300, which is not enough to call buyTokens. Consider calling
	 * buyTokens directly when purchasing tokens from a contract.
	 */
	receive() external payable {
		buyTokens(_msgSender());
	}

	/**
	 * @return the token being sold.
	 */
	function token() public view returns (IERC20) {
		return _token;
	}

	/**
	 * @return the address where funds are collected.
	 */
	function wallet() public view returns (address payable) {
		return _wallet;
	}

	/**
	 * @return the number of token units a buyer gets per wei.
	 */
	function rate() public view returns (uint256) {
		return _rate;
	}

	/**
	 * @return the amount of wei raised.
	 */
	function usdcRaised() public view returns (uint256) {
		return _usdcRaised;
	}

	/**
	 * @return the currentTier calculated based on the amount of usdcRaised
	 */
	function currentTier() public view returns (uint16) {
		return uint16(_usdcRaised.div(tierStep));
	}

	/**
	 * @return the amount of tokens received based on the current state
	 * @param weiAmount The amount of wei to being sent
	 */
	function getTokenAmount(
		uint256 weiAmount
	) external view returns (uint256, uint256) {
		return _getTokenAmount(weiAmount);
	}

	/**
	 * @return the current Initial Wallet Offering state, mostly for display purposes
	 */
	function getCurrentIWOState()
		external
		view
		returns (uint16, uint256, uint256, uint256)
	{
		uint256 usdcLeftThisTier = tierStep - (usdcRaised().mod(tierStep));

		return (currentTier(), usdcLeftThisTier, usdcRaised(), rate());
	}

	/**
	 * @dev low level token purchase ***DO NOT OVERRIDE***
	 * This function has a non-reentrancy guard, so it shouldn't be called by
	 * another `nonReentrant` function.
	 * @param beneficiary Recipient of the token purchase
	 */
	function buyTokens(address beneficiary) public payable nonReentrant {
		require(block.timestamp >= startDate, "IWO not started");
		require(block.timestamp < endDate, "IWO finished");

		uint256 weiAmount = msg.value;
		_preValidatePurchase(beneficiary, weiAmount);

		// calculate token amount to be created and the amount of usdc raised in this purchase
		(uint256 tokens, uint256 usdcAmount) = _getTokenAmount(weiAmount);

		// update state
		_usdcRaised = _usdcRaised.add(usdcAmount);

		_processPurchase(beneficiary, tokens);
		emit TokensPurchased(_msgSender(), beneficiary, usdcAmount, tokens);

		_updatePurchasingState(beneficiary, weiAmount);

		_forwardFunds();
		_postValidatePurchase(beneficiary, weiAmount);
	}

	/**
	 * @dev Validation of an incoming purchase. Use require statements to revert state when conditions are not met.
	 * Use `super` in contracts that inherit from Crowdsale to extend their validations.
	 * Example from CappedCrowdsale.sol's _preValidatePurchase method:
	 *     super._preValidatePurchase(beneficiary, weiAmount);
	 *     require(weiRaised().add(weiAmount) <= cap);
	 * @param beneficiary Address performing the token purchase
	 * @param weiAmount Value in wei involved in the purchase
	 */
	function _preValidatePurchase(
		address beneficiary,
		uint256 weiAmount
	) internal view {
		require(
			beneficiary != address(0),
			"Crowdsale: beneficiary is the zero address"
		);
		require(weiAmount != 0, "Crowdsale: weiAmount is 0");
		this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
	}

	/**
	 * @dev Validation of an executed purchase. Observe state and use revert statements to undo rollback when valid
	 * conditions are not met.
	 * @param beneficiary Address performing the token purchase
	 * @param weiAmount Value in wei involved in the purchase
	 */
	function _postValidatePurchase(
		address beneficiary,
		uint256 weiAmount
	) internal view {
		// solhint-disable-previous-line no-empty-blocks
	}

	/**
	 * @dev Source of tokens. Override this method to modify the way in which the crowdsale ultimately gets and sends
	 * its tokens.
	 * @param beneficiary Address performing the token purchase
	 * @param tokenAmount Number of tokens to be emitted
	 */
	function _deliverTokens(address beneficiary, uint256 tokenAmount) internal {
		IMintableERC20(_token).mint(beneficiary, tokenAmount);
	}

	/**
	 * @dev Executed when a purchase has been validated and is ready to be executed. Doesn't necessarily emit/send
	 * tokens.
	 * @param beneficiary Address receiving the tokens
	 * @param tokenAmount Number of tokens to be purchased
	 */
	function _processPurchase(
		address beneficiary,
		uint256 tokenAmount
	) internal {
		_deliverTokens(beneficiary, tokenAmount);
	}

	/**
	 * @dev Override for extensions that require an internal state to check for validity (current user contributions,
	 * etc.)
	 * @param beneficiary Address receiving the tokens
	 * @param weiAmount Value in wei involved in the purchase
	 */
	function _updatePurchasingState(
		address beneficiary,
		uint256 weiAmount
	) internal {
		// solhint-disable-previous-line no-empty-blocks
	}

	/**
	 * @dev Override to extend the way in which ether is converted to tokens.
	 * @param weiAmount Value in wei to be converted into tokens
	 * @return Number of tokens that can be purchased with the specified _weiAmount
	 */
	function _getTokenAmount(
		uint256 weiAmount
	) internal view returns (uint256, uint256) {
		uint16 _currentTier = currentTier();
		uint256 usdcAmount = getUsdQuota(uint128(weiAmount));
		require(usdcAmount > 0, "invalid usdc amount");

		uint256 _newUsdcRaised = _usdcRaised.add(usdcAmount);

		uint256 totalTokenAmount = 0;
		uint16 _newTier = uint16(_newUsdcRaised.div(tierStep));
		require(_newTier >= _currentTier, "invalid current tier");
		if (_newTier > _currentTier) {
			uint16 numberOfTiersIncreased = _newTier - _currentTier;
			uint256 _usdcAmountLeft = usdcAmount;
			uint256 _partialUsdcRaised = _usdcRaised;
			for (uint16 i = 0; i < numberOfTiersIncreased; i++) {
				uint256 _usdcThisTier = tierStep -
					(_partialUsdcRaised.mod(tierStep));
				uint256 _usdcThisTierRate = _usdcThisTier.mul(_rate);
				totalTokenAmount = totalTokenAmount.add(
					_usdcThisTierRate.div(1 + _currentTier + i)
				);
				_usdcAmountLeft = _usdcAmountLeft.sub(_usdcThisTier);
				_partialUsdcRaised = _partialUsdcRaised.add(_usdcThisTier);
			}
			uint256 _lastUsdcRateLeft = _usdcAmountLeft.mul(_rate);
			totalTokenAmount = totalTokenAmount.add(
				_lastUsdcRateLeft.div(1 + _currentTier + numberOfTiersIncreased)
			);
		} else {
			uint256 usdcAmountRate = usdcAmount.mul(_rate);
			totalTokenAmount = totalTokenAmount.add(
				usdcAmountRate.div(1 + _currentTier)
			);
		}
		require(
			totalTokenAmount > 0 &&
				totalTokenAmount <=
				(usdcAmount.mul(_rate)).div(1 + _currentTier),
			"invalid total token amount"
		);
		return (totalTokenAmount * (10 ** 12), usdcAmount);
	}

	/**
	 * @dev Determines how ETH is stored/forwarded on purchases.
	 */
	function _forwardFunds() internal {
		_wallet.transfer(msg.value);
	}

	/**
	 * @dev Returns the equivalent amount of usd given the weiAmount
	 * @param weiAmount amount wei being sent
	 */
	function getUsdQuota(uint128 weiAmount) internal view returns (uint256) {
		uint256 usdAmount = oracle.usdAmount(weiAmount);
		require(usdAmount > 0, "Invalid oracle amount");

		return usdAmount;
	}
}

