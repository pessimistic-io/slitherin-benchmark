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

	// Address of the token needed for whitelist in tier 1
	IERC20 public immutable whitelistToken;
	uint256 public immutable whitelistTokenAmount;

	// Oracle used to calculate usdQuota based on wei amount sent to the contract
	IOracle public oracle;

	// IWOChoke opening date
	uint256 public immutable startDate;
	// IWOChoke ending date
	uint256 public immutable endDate;

	// tierStep is the amount of USDC needed to jump to the next tier.
	uint256 public constant tierStep = 100000 * 10 ** 6;

	/**
	 * @dev The price formula varies with the current tier such as:
	 * price = initialPrice * (1.312 ** currentTier).
	 * Thus, given an initial price of $0.0128 USD, the first 20 prices are stored in tierPrices array for gas optimization with 7 decimals precision.
	 *
	 * @notice Each tier step is $100.000 USD
	 */
	uint256 public constant decimals = 7;
	uint256 public constant priceDecimals = 10 ** decimals;
	uint256[20] public tierPrices = [
		128000,
		167936,
		220332,
		289075,
		379266,
		497596,
		652845,
		856532,
		1123769,
		1474384,
		1934391,
		2537920,
		3329751,
		4368633,
		5731646,
		7519919,
		9866133,
		12944366,
		16983008,
		22281706
	];

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

	/**
	 * @param __wallet Address where collected funds will be forwarded to
	 * @param __whitelistToken Address of the token used as condition for accessing tier 1
	 * @param __token Address of the token being sold
	 */
	constructor(
		address payable __wallet,
		IMintableERC20 __token,
		IERC20 __whitelistToken,
		uint256 __whitelistTokenAmount,
		address _oracle,
		uint256 _startDate,
		uint256 _endDate
	) {
		require(
			__wallet != address(0),
			'Crowdsale: wallet is the zero address'
		);
		require(
			address(__token) != address(0),
			'Crowdsale: token is the zero address'
		);
		require(
			address(__whitelistToken) != address(0),
			'Crowdsale: whitelist token is the zero address'
		);
		require(
			__whitelistTokenAmount > 0,
			'Crowdsale: whitelistTokenAmount should be higher than zero'
		);
		require(
			address(_oracle) != address(0),
			'Crowdsale: _oracle is the zero address'
		);
		require(_endDate > _startDate, 'Invalid end date');

		_wallet = __wallet;
		_token = __token;
		whitelistToken = __whitelistToken;
		whitelistTokenAmount = __whitelistTokenAmount;
		oracle = IOracle(_oracle);
		startDate = _startDate;
		endDate = _endDate;
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
	 * @return the amount of wei raised.
	 */
	function usdcRaised() public view returns (uint256) {
		return _usdcRaised;
	}

	/**
	 * @return the MAX_TIER available based on tierPrices length
	 */
	function MAX_TIER() public pure returns (uint16) {
		return 19;
	}

	/**
	 * @return the currentTier calculated based on the amount of usdcRaised
	 */
	function currentTier() public view returns (uint16) {
		uint16 _tier = uint16(_usdcRaised.div(tierStep));
		if (_tier > MAX_TIER()) {
			_tier = MAX_TIER();
		}
		return _tier;
	}

	/**
	 * @return the amount of tokens received based on the current state
	 * @param weiAmount The amount of wei to being sent
	 */
	function getTokenAmount(
		uint256 weiAmount,
		address buyer
	) external view returns (uint256, uint256) {
		return _getTokenAmount(weiAmount, buyer);
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
		uint16 _currentTier = currentTier();

		return (
			_currentTier,
			usdcLeftThisTier,
			usdcRaised(),
			tierPrices[_currentTier]
		);
	}

	/**
	 * @dev low level token purchase ***DO NOT OVERRIDE***
	 * This function has a non-reentrancy guard, so it shouldn't be called by
	 * another `nonReentrant` function.
	 * @param beneficiary Recipient of the token purchase
	 */
	function buyTokens(address beneficiary) public payable nonReentrant {
		require(block.timestamp >= startDate, 'IWO not started');
		require(block.timestamp < endDate, 'IWO finished');

		uint256 weiAmount = msg.value;
		_preValidatePurchase(beneficiary, weiAmount);

		// calculate token amount to be created and the amount of usdc raised in this purchase
		(uint256 tokens, uint256 usdcAmount) = _getTokenAmount(
			weiAmount,
			msg.sender
		);

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
			'Crowdsale: beneficiary is the zero address'
		);
		require(weiAmount != 0, 'Crowdsale: weiAmount is 0');
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
		uint256 weiAmount,
		address buyer
	) internal view returns (uint256, uint256) {
		uint16 _currentTier = currentTier();
		uint256 usdcAmount = getUsdQuota(uint128(weiAmount));
		require(usdcAmount > 0, 'invalid usdc amount');

		uint256 _newUsdcRaised = _usdcRaised.add(usdcAmount);

		uint256 totalTokenAmount = 0;
		uint16 _newTier = uint16(_newUsdcRaised.div(tierStep));

		if (_newTier == 0) {
			if (whitelistToken.balanceOf(buyer) < whitelistTokenAmount) {
				_currentTier = 1;
				_newTier = 1;
			}
		} else if (_newTier == 1 && _currentTier == 0) {
			if (whitelistToken.balanceOf(buyer) < whitelistTokenAmount) {
				_currentTier = 1;
			}
		}

		if (_newTier > MAX_TIER()) {
			_newTier = MAX_TIER();
		}

		require(_newTier >= _currentTier, 'invalid new tier');
		if (_newTier > _currentTier) {
			uint16 numberOfTiersIncreased = _newTier - _currentTier;
			uint256 _partialUsdcRaised = _usdcRaised;
			uint256 _usdcAmountLeft = usdcAmount;
			for (uint16 i = 0; i < numberOfTiersIncreased; i++) {
				uint256 _usdcThisTier = tierStep -
					(_partialUsdcRaised.mod(tierStep));
				uint256 _priceThisTier = tierPrices[_currentTier + i];

				totalTokenAmount = totalTokenAmount.add(
					(_usdcThisTier.mul(priceDecimals)).div(_priceThisTier)
				);
				_usdcAmountLeft = _usdcAmountLeft.sub(_usdcThisTier);
				_partialUsdcRaised = _partialUsdcRaised.add(_usdcThisTier);
			}
			uint256 _priceNewTier = tierPrices[
				_currentTier + numberOfTiersIncreased
			];
			totalTokenAmount = totalTokenAmount.add(
				(_usdcAmountLeft.mul(priceDecimals)).div(_priceNewTier)
			);
		} else {
			totalTokenAmount = totalTokenAmount.add(
				(usdcAmount.mul(priceDecimals)).div(tierPrices[_currentTier])
			);
		}
		require(
			totalTokenAmount > 0 &&
				totalTokenAmount <=
				(usdcAmount.mul(priceDecimals)).div(tierPrices[_currentTier]),
			'invalid total token amount'
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
		require(usdAmount > 0, 'Invalid oracle amount');

		return usdAmount;
	}

	/**
	 * @dev Returns the equivalent amount of usd given the weiAmount
	 * @param weiAmount amount wei being sent
	 */
	function usdQuota(uint128 weiAmount) external view returns (uint256) {
		return getUsdQuota(weiAmount);
	}
}

