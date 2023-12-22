// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";

contract IDO is Ownable {
	using SafeERC20 for IERC20Metadata;

	IERC20Metadata public USDCToken;
	IERC20Metadata[] public tokenList;

	mapping(address => bool) whiteList;
	bool public whiteSaleEnabled;
	bool public whiteClaimEnabled;
	mapping(uint => uint) public whiteTotalBuy;
	mapping(uint => mapping(address => uint)) public whiteTokenBalances;

	bool public publicSaleEnabled;
	bool public publicClaimEnabled;
	mapping(uint => uint) public publicTotalBuy;
	mapping(uint => mapping(address => uint)) public publicTokenBalances;

	constructor(IERC20Metadata _eagle, IERC20Metadata _bear, IERC20Metadata _panda, IERC20Metadata _usdc) {
		tokenList.push(_eagle);
		tokenList.push(_bear);
		tokenList.push(_panda);
		USDCToken = _usdc;
	}

	function setWhiteList(address[] calldata _accounts) public onlyOwner {
		for (uint i = 0; i < _accounts.length; i++) {
			whiteList[_accounts[i]] = true;
		}
	}

	function unsetWhiteList(address[] calldata _accounts) public onlyOwner {
		for (uint i = 0; i < _accounts.length; i++) {
			whiteList[_accounts[i]] = false;
		}
	}

	function setWhiteSaleEnabled(bool _whiteSaleEnabled) public onlyOwner {
		whiteSaleEnabled = _whiteSaleEnabled;
	}

	function setWhiteClaimEnabled(bool _whiteClaimEnabled) public onlyOwner {
		whiteClaimEnabled = _whiteClaimEnabled;
	}

	function whiteBuyToken(uint tokenIndex, uint amount) public {
		require(whiteSaleEnabled, "white list pre-sale closed");
		require(whiteList[msg.sender], "you are not white");
		require(amount >= 1e18, "minimum purchase amount is 1");
		uint decimals = USDCToken.decimals();
		uint usdcAmount = (amount * 10 ** decimals) / (1e18);
		whiteTotalBuy[tokenIndex] += amount;
		whiteTokenBalances[tokenIndex][msg.sender] += amount;
		require(whiteTokenBalances[tokenIndex][msg.sender] <= 500 * 1e18, "exceed maximum");
		USDCToken.safeTransferFrom(msg.sender, address(this), usdcAmount);
	}

	function handleGetWhiteMinToken() internal view returns (uint) {
		uint minAmount = whiteTotalBuy[0];
		uint minTokenIndex = 0;
		for (uint i = 1; i <= 2; i++) {
			if (whiteTotalBuy[i] < minAmount) {
				minAmount = whiteTotalBuy[i];
				minTokenIndex = i;
			}
		}
		return minAmount;
	}

	function whiteReceiveToken(uint tokenIndex) external {
		require(whiteClaimEnabled, "white list claim closed");
		require(whiteList[msg.sender], "you are not white");
		uint userAmount = whiteTokenBalances[tokenIndex][msg.sender];
		require(userAmount > 0, "You don't have a token balance");
		uint currentWhiteTotalBuy = whiteTotalBuy[tokenIndex];
		require(currentWhiteTotalBuy > 0, "currentWhiteTotalBuy is zero");
		uint minAmount = handleGetWhiteMinToken();
		uint mintUserAmount = (userAmount * minAmount) / currentWhiteTotalBuy;
		uint refundTokenAmount = userAmount - mintUserAmount;

		if (refundTokenAmount > 0) {
			uint decimals = USDCToken.decimals();
			uint usdcTokenAmount = (refundTokenAmount * 10 ** decimals) / 1e18;
			USDCToken.safeTransfer(msg.sender, usdcTokenAmount);
		}

		if (mintUserAmount > 0) {
			IERC20Metadata _token = tokenList[tokenIndex];
			_token.safeTransfer(msg.sender, mintUserAmount);
		}
		whiteTokenBalances[tokenIndex][msg.sender] = 0;
	}

	function getWhiteReceiveAmount(uint tokenIndex, address account) public view returns (uint, uint) {
		uint userAmount = whiteTokenBalances[tokenIndex][account];
		uint currentWhiteTotalBuy = whiteTotalBuy[tokenIndex];
		uint minAmount = handleGetWhiteMinToken();
		if (currentWhiteTotalBuy == 0) {
			return (0, 0);
		}
		uint mintUserAmount = (userAmount * minAmount) / currentWhiteTotalBuy;
		uint refundTokenAmount = userAmount - mintUserAmount;
		uint decimals = USDCToken.decimals();
		uint usdcTokenAmount = (refundTokenAmount * 10 ** decimals) / 1e18;
		return (mintUserAmount, usdcTokenAmount);
	}

	function setPublicSaleEnabled(bool _publicSaleEnabled) public onlyOwner {
		publicSaleEnabled = _publicSaleEnabled;
	}

	function setPublicClaimEnabled(bool _publicClaimEnabled) public onlyOwner {
		publicClaimEnabled = _publicClaimEnabled;
	}

	function publicBuyToken(uint tokenIndex, uint amount) public {
		require(publicSaleEnabled, "public-sale closed");
		require(amount >= 1e18, "minimum purchase amount is 1");
		uint decimals = USDCToken.decimals();
		uint usdcAmount = (amount * 11 * 10 ** decimals) / 10 / (1e18);
		publicTotalBuy[tokenIndex] += amount;
		publicTokenBalances[tokenIndex][msg.sender] += amount;
		require(publicTokenBalances[tokenIndex][msg.sender] <= 500 * 1e18, "exceed maximum");
		USDCToken.safeTransferFrom(msg.sender, address(this), usdcAmount);
	}

	function handleGetPublicMinToken() internal view returns (uint) {
		uint minAmount = publicTotalBuy[0];
		uint minTokenIndex = 0;
		for (uint i = 1; i <= 2; i++) {
			if (publicTotalBuy[i] < minAmount) {
				minAmount = publicTotalBuy[i];
				minTokenIndex = i;
			}
		}
		return minAmount;
	}

	function publicReceiveToken(uint tokenIndex) external {
		require(publicClaimEnabled, "public list claim closed");
		uint userAmount = publicTokenBalances[tokenIndex][msg.sender];
		require(userAmount > 0, "You don't have a token balance");
		uint currentPublicTotalBuy = publicTotalBuy[tokenIndex];
		require(currentPublicTotalBuy > 0, "currentPublicTotalBuy is zero");
		uint minAmount = handleGetPublicMinToken();
		uint mintUserAmount = (userAmount * minAmount) / currentPublicTotalBuy;
		uint refundUsdcAmount = userAmount - mintUserAmount;

		if (refundUsdcAmount > 0) {
			uint decimals = USDCToken.decimals();
			uint usdcTokenAmount = (((refundUsdcAmount * 11) / 10) * 10 ** decimals) / 1e18;
			USDCToken.safeTransfer(msg.sender, usdcTokenAmount);
		}

		if (mintUserAmount > 0) {
			IERC20Metadata _token = tokenList[tokenIndex];
			_token.safeTransfer(msg.sender, mintUserAmount);
		}

		publicTokenBalances[tokenIndex][msg.sender] = 0;
	}

	function getPublicReceiveToken(uint tokenIndex, address account) public view returns (uint, uint) {
		uint userAmount = publicTokenBalances[tokenIndex][account];
		uint currentPublicTotalBuy = publicTotalBuy[tokenIndex];
		if (currentPublicTotalBuy == 0) {
			return (0, 0);
		}
		uint minAmount = handleGetPublicMinToken();
		uint mintUserAmount = (userAmount * minAmount) / currentPublicTotalBuy;
		uint refundUsdcAmount = userAmount - mintUserAmount;
		uint decimals = USDCToken.decimals();
		uint usdcTokenAmount = (((refundUsdcAmount * 11) / 10) * 10 ** decimals) / 1e18;
		return (mintUserAmount, usdcTokenAmount);
	}

	function withdrawToken(address _token, address _to, uint256 _amount) external onlyOwner {
		IERC20Metadata token = IERC20Metadata(_token);
		token.safeTransfer(_to, _amount);
	}
}

