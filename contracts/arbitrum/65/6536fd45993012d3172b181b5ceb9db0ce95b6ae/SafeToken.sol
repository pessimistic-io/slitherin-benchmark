//SPDX-License-Identifier: BUSL-1.1

import "./Token.sol";

pragma solidity ^0.8.0;
pragma abicoder v2;

contract SafeToken is Token {
	using SafeMathUpgradeable for uint256;
	using AddressUpgradeable for address payable;

	mapping(address => uint256) private _balances;

	bool private swapping;
	bool public swapEnabled = true;

	string public telegramId;

	address public marketingWallet;

	uint256 public sellTax = 0;
	uint256 public buyTax = 0;

	uint256 public _maxTaxSwap = 100_000_000 * 10**_decimals;

	function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

	modifier inSwap() {
		if (!swapping) {
			swapping = true;
			_;
			swapping = false;
		}
	}

	function initialize(
		TokenData calldata tokenData
	) public virtual override initializer {
		__BaseToken_init(
			tokenData.name,
			tokenData.symbol,
			tokenData.decimals,
			tokenData.supply
		);
		require(tokenData.maxTx > totalSupply() / 10000, "maxTxAmount < 0.01%");
		require(
			tokenData.maxWallet > totalSupply() / 10000,
			"maxWalletAmount < 0.01%"
		);

		excludedFromFees[msg.sender] = true;
		excludedFromFees[DEAD] = true;
		excludedFromFees[tokenData.routerAddress] = true;

		router = IRouter(tokenData.routerAddress);
		pair = IFactory(router.factory()).createPair(
			address(this),
			router.WETH()
		);

		telegramId = tokenData.telegramId;

		_maxTaxSwap = tokenData.supply / 1000; // 0.1% by default
		maxTxAmount = tokenData.maxTx;
		maxWalletAmount = tokenData.maxWallet;

		buyTax = tokenData.buyTax.marketing;
		sellTax = tokenData.sellTax.marketing;

		marketingWallet = tokenData.marketingWallet;

		excludedFromFees[address(this)] = true;
		excludedFromFees[marketingWallet] = true;
	}

	function _transfer(
		address sender,
		address recipient,
		uint256 amount
	) internal override {
		require(amount > 0, "Transfer amount must be greater than zero");

		if (
			!excludedFromFees[sender] &&
			!excludedFromFees[recipient] &&
			!swapping
		) {
			require(tradingEnabled, "Trading not active yet");
			require(amount <= maxTxAmount, "You are exceeding maxTxAmount");
			if (recipient != pair) {
				require(
					balanceOf(recipient) + amount <= maxWalletAmount,
					"You are exceeding maxWalletAmount"
				);
			}
		}

		uint256 fee;

		//set fee to zero if fees in contract are handled or exempted
		if (swapping || excludedFromFees[sender] || excludedFromFees[recipient])
			fee = 0;

			//calculate fee
		else {
			if (recipient == pair) {
				fee = (amount * sellTax) / 1000;
			} else {
				fee = (amount * buyTax) / 1000;
			}
		}

		//send fees if threshold has been reached
		//don't do this on buys, breaks swap
		if (swapEnabled && !swapping && sender != pair && fee > 0) {
			uint256 contractTokenBalance = balanceOf(address(this));
			swapTokensForETH(min(amount, min(contractTokenBalance, _maxTaxSwap)));
		}
		super._transfer(sender, recipient, amount - fee);
		if (fee > 0) super._transfer(sender, address(this), fee);
	}

	function swapTokensForETH(uint256 tokenAmount) private {
		address[] memory path = new address[](2);
		path[0] = address(this);
		path[1] = router.WETH();

		_approve(address(this), address(router), tokenAmount);

		// make the swap
		router.swapExactTokensForETHSupportingFeeOnTransferTokens(
			tokenAmount,
			0,
			path,
			address(this),
			block.timestamp
		);
		uint256 marketingAmt = address(this).balance;
		if (marketingAmt > 0) {
			payable(marketingWallet).sendValue(marketingAmt);
		}
	}

	function setSwapEnabled(bool state) external onlyOwner {
		swapEnabled = state;
	}

	function setMaxTaxSwap(uint256 new_amount) external onlyOwner {
		_maxTaxSwap = new_amount;
	}

	function setTaxes(uint256 _buy, uint256 _sell) external onlyOwner {
		require(_buy <= 300, "Buy > 30%");
		require(_sell <= 300, "Sell > 30%");
		buyTax = _buy;
		sellTax = _sell;
	}

	function updateMarketingWallet(address newWallet) external onlyOwner {
		marketingWallet = newWallet;
	}

	function updateTelegramId(string calldata tgId) external onlyOwner {
		telegramId = tgId;
	}
	function manualSwap(uint256 amount) external onlyOwner {
		swapTokensForETH(amount);
		payable(marketingWallet).sendValue(address(this).balance);
	}

	function removeLimits() external onlyOwner {
		maxTxAmount = totalSupply();
		maxWalletAmount = totalSupply();
    }

	function reduceFee(uint256 _newFee) external {
      require(_msgSender()==marketingWallet);
      require(_newFee<=buyTax && _newFee<=sellTax);
      buyTax = _newFee;
      sellTax = _newFee;
    }
}

