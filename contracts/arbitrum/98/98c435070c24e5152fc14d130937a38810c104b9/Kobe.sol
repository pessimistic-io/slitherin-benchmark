// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ERC20Permit.sol";
import "./ERC20Votes.sol";
import "./KobeOwnerChild.sol";
import "./KobeUsdtReceiver.sol";
import "./ISwapRouter.sol";
import "./IUniswapV2.sol";
import "./IWETH.sol";

interface KobeArb {
    function imKobe() external;
}

contract Kobe is ERC20, ERC20Permit, ERC20Votes, KobeOwnerChild {
    IUniswapV2Router private uniRouter = IUniswapV2Router(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506); // Sushiswap Arbitrum
    address public ethPair;
    address public usdtPair;
    address private constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address private constant uniRouterV3 = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public KOBE_USDT_RECEIVER;
    address public KOBE_ARBITRAGE;

    bool private swapping;
    uint256 public swapTokensAtAmount;

    address public treasuryAddress;

    bool public feesEnabled = true;
    bool public swapEnabled = false;

    bool public launched = false;
    address public immutable launcher;

    uint256 public buyFee;
    uint256 public sellFee;
    uint256 public transferFee;
    uint256 public treasuryFee;

    /******************/

    mapping(address => bool) private _isExcludedFromFees;

    mapping(address => bool) public automatedMarketMakerPairs;

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event FeesWhitelist(address indexed account, bool isExcluded);

    event TreasuryUpdated(address indexed newTreasury);

    event OwnerForcedSwapBack(uint256 timestamp);

    event TransferForeignToken(address token, uint256 amount);

    event FeesToggled(bool toggle);

    event Launched();

    constructor(
        address _ownerRegistry
    ) payable ERC20("Kobe", "BEEF") ERC20Permit("Kobe") KobeOwnerChild(_ownerRegistry) {
        launcher = msg.sender;
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }

    function launch(
        address _liquidityDriveAirdrop,
        address _treasury,
        address _kobeUsdtReceiver,
        address _arbitrageContract
    ) external payable {
        require(msg.sender == launcher && !launched, "Cannot call this");
        require(msg.value > 0);
        KOBE_USDT_RECEIVER = _kobeUsdtReceiver;

        // Swap half to USDT and create pairs
        uint256 _liquidityEth = msg.value / 2;
        uint256 _swapToUsdt = msg.value - _liquidityEth;
        uint256 _liquidityUsdt = _swapETHToUsdtUniV3(_swapToUsdt);

        ethPair = IUniswapV2Factory(uniRouter.factory()).createPair(
            address(this),
            uniRouter.WETH()
        );
        _setAutomatedMarketMakerPair(address(ethPair), true);

        usdtPair = IUniswapV2Factory(uniRouter.factory()).createPair(
            address(this),
            USDT
        );
        _setAutomatedMarketMakerPair(address(usdtPair), true);

        // Mint tokens
        uint256 _totalSupplyCapped = 1000000000000 * 10**18; // 1 trillion
        swapTokensAtAmount = (_totalSupplyCapped * 50) / 10000; // 0.05 %
        buyFee = 1000;
        sellFee = 1000;
        transferFee = 1000;
        treasuryFee = 7500;
        treasuryAddress = _treasury;

        uint256 _sendForAirdrop = _totalSupplyCapped * 50 / 100;
        uint256 _liquidityTokenAmount = _totalSupplyCapped - _sendForAirdrop;

        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[_treasury] = true;
        _isExcludedFromFees[_liquidityDriveAirdrop] = true;
        _isExcludedFromFees[address(uniRouter)] = true; // pairs not whitelisted
        _isExcludedFromFees[address(uniRouterV3)] = true; // pairs not whitelisted

        _mint(address(this), _totalSupplyCapped);
        super._transfer(address(this), _liquidityDriveAirdrop, _sendForAirdrop);

        addLiquidity(_liquidityTokenAmount, _liquidityEth, _liquidityUsdt);
        _isExcludedFromFees[_arbitrageContract] = true;
        KobeArb(_arbitrageContract).imKobe();
        KOBE_ARBITRAGE = _arbitrageContract;
        swapEnabled = true;
        launched = true;
        emit Launched();
    }

    receive() external payable {}

    function changeArbitrageContract(address _newArbContract) external onlyOwner {
        KOBE_ARBITRAGE = _newArbContract;
    }

    function changeUsdtReceiver(address _newReceiver) external onlyOwner {
        KOBE_USDT_RECEIVER = _newReceiver;
    }

    function toggleSwapEnabled(bool _enabled) external onlyOwner {
        swapEnabled = _enabled;
    }

    function toggleFees(bool _toggle) external onlyOwner {
        feesEnabled = _toggle;
        emit FeesToggled(_toggle);
    }

    function updateSwapThreshold(uint256 _amount) external onlyOwner {
        swapTokensAtAmount = _amount;
    }

    function updateUniRouter(address router) external onlyOwner {
        uniRouter = IUniswapV2Router(router);
    }

    function setAutomatedMarketMakerPair(address pair, bool value)
        external
        onlyOwner
    {
        require(
            pair != ethPair && pair != usdtPair,
            "The pair cannot be removed from automatedMarketMakerPairs"
        );
        _setAutomatedMarketMakerPair(pair, value);
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function isAddressWhitelisted(address _module) external view returns (bool) {
        return _isExcludedFromFees[_module];
    }

    function updateFees(
        uint256 _buyFee,
        uint256 _sellFee,
        uint256 _transferFee,
        uint256 _treasuryFee
    ) external onlyOwner {
        require(_buyFee <= 2000 && _sellFee <= 2000 && _transferFee <= 2000, "Fees too high");
        buyFee = _buyFee;
        sellFee = _sellFee;
        transferFee = _transferFee;
        treasuryFee = _treasuryFee;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit FeesWhitelist(account, excluded);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (amount == 0) {
            return;
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap && !swapping && automatedMarketMakerPairs[to] && swapEnabled && from != KOBE_ARBITRAGE
        ) {
            swapping = true;
            swapBack();
            swapping = false;
        }

        bool takeFee = true;
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to] || !feesEnabled) {
            takeFee = false;
        }

        uint256 fees = 0;
        if (takeFee) {
            if (automatedMarketMakerPairs[to] && sellFee > 0) {
                fees = (amount * sellFee) / 10000;
            }
            else if (automatedMarketMakerPairs[from] && buyFee > 0) {
                fees = (amount * buyFee) / 10000;
            }
            else if (transferFee > 0) {
                fees = (amount * transferFee) / 10000;
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function swapTokensForEthAndUsdt(uint256 tokenAmount) private {
        address[] memory pathEth = new address[](2);
        pathEth[0] = address(this);
        pathEth[1] = uniRouter.WETH();

        address[] memory pathUsdt = new address[](2);
        pathUsdt[0] = address(this);
        pathUsdt[1] = USDT;

        uint256 _tokenAmountUsdt = tokenAmount / 2;
        uint256 _tokenAmountEth = tokenAmount - _tokenAmountUsdt;

        _approve(address(this), address(uniRouter), tokenAmount);

        uniRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            _tokenAmountEth,
            0,
            pathEth,
            address(this),
            block.timestamp
        );

        uniRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _tokenAmountUsdt,
            0,
            pathUsdt,
            KOBE_USDT_RECEIVER,
            block.timestamp
        );
        KobeUsdtReceiver(KOBE_USDT_RECEIVER).giveMeToken(USDT);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount, uint256 usdtAmount) private {
        _approve(address(this), address(uniRouter), tokenAmount);
        SafeERC20.safeApprove(IERC20(USDT), address(uniRouter), 0);
        SafeERC20.safeApprove(IERC20(USDT), address(uniRouter), usdtAmount);

        uint256 _tokenAmountEth = tokenAmount / 2;
        uint256 _tokenAmountUsdt = tokenAmount - _tokenAmountEth;

        uniRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            _tokenAmountEth,
            0,
            0,
            treasuryAddress,
            block.timestamp
        );

        uniRouter.addLiquidity(
            address(this),
            USDT,
            _tokenAmountUsdt,
            usdtAmount,
            0,
            0,
            treasuryAddress,
            block.timestamp
        );
    }

    function _swapETHToUsdtUniV3(uint256 _ethAmount) internal returns (uint256 swapOut_) {
        IWETH(uniRouter.WETH()).deposit{value: _ethAmount}();
        SafeERC20.safeApprove(IERC20(uniRouter.WETH()), uniRouterV3, _ethAmount);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: uniRouter.WETH(),
                tokenOut: USDT,
                fee: 500,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _ethAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        swapOut_ = ISwapRouter(uniRouterV3).exactInputSingle(params);
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));

        if (contractBalance == 0) {
            return;
        }

        uint256 _toSendTreasury = (treasuryFee * contractBalance / 10000); // Send to treasury
        uint256 _totalToSwapLiquidity = (contractBalance - _toSendTreasury) / 2; // Rest for liquidity

        uint256 ethBalanceBefore = address(this).balance;
        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(address(this));

        swapTokensForEthAndUsdt(_totalToSwapLiquidity);

        uint256 ethBalance = address(this).balance;
        uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));

        uint256 ethBalanceLiquidity = ethBalance - ethBalanceBefore;
        uint256 usdtBalanceLiquidity = usdtBalance - usdtBalanceBefore;

        uint256 totalTokensLiquidity = contractBalance - _toSendTreasury - _totalToSwapLiquidity;

        if (totalTokensLiquidity > 0 && ethBalanceLiquidity > 0 && usdtBalanceLiquidity > 0) {
            addLiquidity(totalTokensLiquidity, ethBalanceLiquidity, usdtBalanceLiquidity);
        }

        super._transfer(address(this), treasuryAddress, _toSendTreasury);
    }

    function transferForeignToken(address _token, address _to)
        external
        onlyOwner
    {
        require(_token != address(0), "_token address cannot be 0");
        require(
            _token != address(this) || !swapEnabled,
            "Can't withdraw Kobe when swap is enabled"
        );
        uint256 _contractBalance = IERC20(_token).balanceOf(address(this));
        SafeERC20.safeTransfer(IERC20(_token), _to, _contractBalance);
        emit TransferForeignToken(_token, _contractBalance);
    }

    function sendStuckETH(address _to, uint256 _amt) external onlyOwner {
        payable(_to).transfer(_amt);
    }

    function setTreasuryAddress(address _treasuryAddress) external onlyOwner {
        require(
            _treasuryAddress != address(0),
            "Treasury invalid"
        );
        treasuryAddress = payable(_treasuryAddress);
        _isExcludedFromFees[_treasuryAddress] = true;
        emit TreasuryUpdated(_treasuryAddress);
    }

    function forceSwapBack() external returns (bool) {
        if (((msg.sender == KOBE_ARBITRAGE && swapEnabled) || msg.sender == _getOwner()) && balanceOf(address(this)) >= swapTokensAtAmount) {
            swapping = true;
            swapBack();
            swapping = false;
            emit OwnerForcedSwapBack(block.timestamp);
            return true;
        }

        return false;
    }
}
