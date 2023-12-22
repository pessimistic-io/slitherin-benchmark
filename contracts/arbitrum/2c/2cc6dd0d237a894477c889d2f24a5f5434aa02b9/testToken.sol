// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ICamelotRouter.sol";
import "./ICamelotFactory.sol";

contract testToken is ERC20, Ownable {
    uint8 private constant _decimals = 6;
    uint256 private constant TOTAL_SUPPLY = 69_000_000_000_000 * 10**_decimals ;

    bool private _inSwapAndLiquify;

    bool public swapAndTreasureEnabled;

    mapping(address => bool) public excludedFromFee;

    ICamelotRouter public uniswapV2Router;
    address public uniswapV2Pair;

    address payable public treasuryWallet;
    address public marketingWallet;
    uint8 public treasuryFeeOnBuy;
    uint8 public treasuryFeeOnSell;

    uint256 public maxTxAmountSell;
    uint256 public swapAtAmount;

    event TransferEnabled(uint256 time);
    event FeeUpdated(uint8 buyFee, uint8 sellFee);
    event SwapAtUpdated(uint256 swapAtAmount);
    event MaxSellAmountUpdated(uint256 newAmount);
    event SwapAndTreasureEnabled(bool state);

    modifier lockTheSwap() {
        _inSwapAndLiquify = true;
        _;
        _inSwapAndLiquify = false;
    }


    // --------------------- CONSTRUCT ---------------------

    constructor(address _treasure, address _marketing, address _router) ERC20('token name3', 'ticker3') {
        treasuryWallet = payable(_treasure);
        marketingWallet = _marketing;
        uniswapV2Router = ICamelotRouter(_router);

        excludedFromFee[msg.sender] = true;
        excludedFromFee[address(this)] = true;
        excludedFromFee[treasuryWallet] = true;
        excludedFromFee[marketingWallet] = true;

        swapAndTreasureEnabled = true;

        _mint(msg.sender, TOTAL_SUPPLY);

        treasuryFeeOnBuy = 3;
        treasuryFeeOnSell = 3;

        swapAtAmount = totalSupply() / 100000; // 0.001%
        maxTxAmountSell = totalSupply() / 1000; // 0.1%
    }

    // --------------------- VIEWS ---------------------

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    // --------------------- INTERNAL ---------------------

    function _transfer(address from, address to, uint256 amount ) internal override {
        require(to != address(0), 'Transfer to zero address');
        require(amount != 0, 'Transfer amount must be not zero');

        // maxTxAmount
        if (
            !excludedFromFee[from]
            && !excludedFromFee[to]
            && !excludedFromFee[tx.origin]
            && to == uniswapV2Pair
            && from != address(uniswapV2Router)
        ) {
            require(amount <= maxTxAmountSell, 'Max tx limit');
        }

        // swapAndSendTreasure
        if (
            swapAndTreasureEnabled
            && balanceOf(address(this)) >= swapAtAmount
            && !_inSwapAndLiquify
            && to == uniswapV2Pair
            && !excludedFromFee[from]
            && !excludedFromFee[tx.origin]
        ) {
            _swapAndSendTreasure(swapAtAmount);
        }

        // fees
        if (
            (from != uniswapV2Pair && to != uniswapV2Pair)
            || excludedFromFee[from]
            || excludedFromFee[to]
            || excludedFromFee[tx.origin]
        ) {
            super._transfer(from, to, amount);
        } else {
            uint256 fee;
            if (to == uniswapV2Pair) {
                fee = amount / 100 * treasuryFeeOnSell;
                //to treasury
                if (fee != 0) {
                    super._transfer(from, marketingWallet, fee);
                }
            } else {
                fee = amount / 100 * treasuryFeeOnBuy;
                //to contract
                if (fee != 0) {
                    super._transfer(from, address(this), fee);
                }
            }

            super._transfer(from, to, amount - fee);
        }
    }

    function _swapAndSendTreasure(uint256 _amount) internal lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), _amount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(_amount, 0, path, address(this), address(0), block.timestamp);

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            (bool success,) = treasuryWallet.call{ value: ethBalance }('');
            require(success, "ETH transfer failed");
        }
    }

    // --------------------- OWNER ---------------------
    function setExcludedFromFee(address _account, bool _state) external onlyOwner {
        require(excludedFromFee[_account] != _state, 'Already set');
        excludedFromFee[_account] = _state;
    }

    function setTreasuryFee(uint8 _feeOnBuy, uint8 _feeOnSell) external onlyOwner {
        require(_feeOnBuy <= 5 && _feeOnSell <= 5, 'fee cannot exceed 5%');
        treasuryFeeOnBuy = _feeOnBuy;
        treasuryFeeOnSell = _feeOnSell;

        emit FeeUpdated(_feeOnBuy, _feeOnSell);
    }

    function setTreasury(address payable _treasuryWallet) external onlyOwner {
        treasuryWallet = _treasuryWallet;
        excludedFromFee[treasuryWallet] = true;
    }

    function setMarketingWallet(address _marketing) external onlyOwner {
        marketingWallet = _marketing;
        excludedFromFee[marketingWallet] = true;
    }

    function setSwapAndTreasureEnabled(bool _state) external onlyOwner {
        swapAndTreasureEnabled = _state;

        emit SwapAndTreasureEnabled(_state);
    }

    function setSwapAtAmount(uint256 _amount) external onlyOwner {
        require(_amount > 0, "zero input");
        swapAtAmount = _amount;

        emit SwapAtUpdated(_amount);
    }

    function setMaxTxAmountSell(uint256 _amount) external onlyOwner {
        require(_amount >= totalSupply()/10000, "Cannot be less than 0.01%");
        maxTxAmountSell = _amount;

        emit MaxSellAmountUpdated(_amount);
    }

    function setPair(address pair) external onlyOwner {
        uniswapV2Pair = pair;
    }

    function recover(address _token, uint256 _amount) external onlyOwner {
        if (_token != address(0)) {
			IERC20(_token).transfer(msg.sender, _amount);
		} else {
			(bool success, ) = payable(msg.sender).call{ value: _amount }("");
			require(success, "Can't send ETH");
		}
	}

    // --------------------- PERIPHERALS ---------------------

    // to recieve ETH from uniswapV2Router when swapping
    receive() external payable {}

    function emergencyWithdraw() external onlyOwner {
        payable(owner()).call{ value: address(this).balance }('');
    }

}
