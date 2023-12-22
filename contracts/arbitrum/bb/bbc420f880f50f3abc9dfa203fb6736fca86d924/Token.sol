//SPDX-License-Identifier: MIT

// ░▒█▀▀▀█░█▀▄▀█░█▀▀▄░█▀▀▄░▀█▀░█▀▀▄░▀█▀
// ░░▀▀▀▄▄░█░▀░█░█▄▄█░█▄▄▀░░█░▒█▄▄█░▒█░
// ░▒█▄▄▄█░▀░░▒▀░▀░░▀░▀░▀▀░░▀░▒█░▒█░▄█▄

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";

pragma solidity ^0.8.17;

interface DexFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

interface DexRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract SmartAI is ERC20, Ownable {
    struct Tax {
        uint256 marketingTax;
    }

    uint256 private constant _totalSupply = 5e9 * 1e18;
    mapping(address => uint256) private _balances;

    //Router
    DexRouter public uniswapRouter;
    address public pairAddress;

    //Taxes
    Tax public buyTaxes = Tax(5);
    Tax public sellTaxes = Tax(5);
    uint256 public totalBuyFees = 5;
    uint256 public totalSellFees = 5;

    //Whitelisting from taxes/maxwallet/txlimit/etc
    mapping(address => bool) private whitelisted;

    //Swapping
    uint256 public swapTokensAtAmount = _totalSupply / 100000; //after 0.001% of total supply, swap them
    bool public swapAndLiquifyEnabled = true;
    bool public isSwapping = false;
    bool public tradingStatus = false;

    //max amoutns
    uint256 public maxBuy = (_totalSupply * 25) / 1000;
    uint256 public maxSell = (_totalSupply * 25) / 1000;

    //Put Marketing Wallet Here
    address public MarketingWallet = 0x56773Db5EA7c215Dab4631b056E2209eAb64a492;

    constructor() ERC20("SmartAI", "SAT") {
        uniswapRouter = DexRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506); // Put Arbitrum Dex Router Address Here
        pairAddress = DexFactory(uniswapRouter.factory()).createPair(
            address(this),
            uniswapRouter.WETH()
        );
        whitelisted[msg.sender] = true;
        whitelisted[address(uniswapRouter)] = true;
        whitelisted[address(this)] = true;
        _mint(msg.sender, _totalSupply);
    }

    function enableTrading() external onlyOwner {
        tradingStatus = true;
    }

    function setMarketingWallet(address _newMarketing) external onlyOwner {
        require(
            MarketingWallet != address(0),
            "new marketing wallet can not be dead address!"
        );
        MarketingWallet = _newMarketing;
    }

    function setBuyFees(uint256 _marketingTax) external onlyOwner {
        buyTaxes.marketingTax = _marketingTax;
        totalBuyFees = _marketingTax;
        require(totalBuyFees <= 25, "can not set fees higher than 25%");
    }

    function setSellFees(uint256 _marketingTax) external onlyOwner {
        sellTaxes.marketingTax = _marketingTax;
        totalSellFees = _marketingTax;
        require(totalSellFees <= 25, "can not set fees higher than 25%");
    }

    function setSwapTokensAtAmount(uint256 _newAmount) external onlyOwner {
        require(
            _newAmount > 0,
            "Radiate : Minimum swap amount must be greater than 0!"
        );
        swapTokensAtAmount = _newAmount;
    }

    function toggleSwapping() external onlyOwner {
        swapAndLiquifyEnabled = (swapAndLiquifyEnabled == true) ? false : true;
    }

    function setWhitelistStatus(
        address _wallet,
        bool _status
    ) external onlyOwner {
        whitelisted[_wallet] = _status;
    }

    function checkWhitelist(address _wallet) external view returns (bool) {
        return whitelisted[_wallet];
    }

    function setMaxSell(uint256 maxSell_) external onlyOwner {
        require(
            maxSell_ >= totalSupply() / 10000,
            "can not set max sell less than 0.01% of supply"
        );
        maxSell = maxSell_;
    }

    function setMaxBuy(uint256 maxBuy_) external onlyOwner {
        require(
            maxBuy_ >= totalSupply() / 10000,
            "can not set max buy less than 0.01% of supply"
        );
        maxBuy = maxBuy_;
    }

    function _takeTax(
        address _from,
        address _to,
        uint256 _amount
    ) internal returns (uint256) {
        if (whitelisted[_from] || whitelisted[_to]) {
            return _amount;
        }
        require(tradingStatus, "Trading is not enabled yet!");
        uint256 totalTax = 0;
        if (_to == pairAddress) {
            totalTax = totalSellFees;
            require(_amount <= maxSell, "can not sell more than max sell");
        } else if (_from == pairAddress) {
            totalTax = totalBuyFees;
            require(_amount <= maxBuy, "can not sell more than max sell");
        }
        uint256 tax = 0;
        if (totalTax > 0) {
            tax = (_amount * totalTax) / 100;
            super._transfer(_from, address(this), tax);
        }
        return (_amount - tax);
    }

    function _transfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual override {
        require(_from != address(0), "transfer from address zero");
        require(_to != address(0), "transfer to address zero");
        uint256 toTransfer = _takeTax(_from, _to, _amount);

        bool canSwap = balanceOf(address(this)) >= swapTokensAtAmount;
        if (
            swapAndLiquifyEnabled &&
            pairAddress == _to &&
            canSwap &&
            !whitelisted[_from] &&
            !whitelisted[_to] &&
            !isSwapping
        ) {
            isSwapping = true;
            manageTaxes();
            isSwapping = false;
        }
        super._transfer(_from, _to, toTransfer);
    }

    function manageTaxes() internal {
        swapToETH(balanceOf(address(this)));
        (bool success, ) = MarketingWallet.call{value: address(this).balance}(
            ""
        );
    }

    function swapToETH(uint256 _amount) internal {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapRouter.WETH();
        _approve(address(this), address(uniswapRouter), _amount);
        uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            _amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function withdrawStuckETH() external onlyOwner {
        (bool success, ) = address(msg.sender).call{
            value: address(this).balance
        }("");
        require(success, "transfering ETH failed");
    }

    function withdrawStuckTokens(address erc20_token) external onlyOwner {
        bool success = IERC20(erc20_token).transfer(
            msg.sender,
            IERC20(erc20_token).balanceOf(address(this))
        );
        require(success, "trasfering tokens failed!");
    }

    receive() external payable {}
}

