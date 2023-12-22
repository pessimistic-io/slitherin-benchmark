// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./Context.sol";
import "./ERC20.sol";
import "./draft-IERC20Permit.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./ICamelotFactory.sol";
import "./IWETH.sol";
import "./IUniswapV2Router01.sol";
import "./IJackpot.sol";
import "./IDogeBonusPool.sol";
import "./ICamelotRouter.sol";

contract AiFLOKI is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event SwapBack(
        uint256 burn,
        uint256 gov1,
        uint256 gov2,
        uint256 liquidity,
        uint256 jackpot,
        uint256 bonus,
        uint256 dev,
        uint256 timestamp
    );
    event Trade(
        address user,
        address pair,
        uint256 amount,
        uint256 side,
        uint256 circulatingSupply,
        uint256 timestamp
    );
    event AddLiquidity(
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 timestamp
    );

    bool public swapEnabled = true;
    bool public addLiquidityEnabled = true;

    bool public inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public canAddLiquidityBeforeLaunch;

    uint256 private burnFee;
    uint256 public gov1Fee;
    uint256 public gov2Fee;
    uint256 private liquidityFee;
    uint256 private jackpotFee;
    uint256 private bonusFee;
    uint256 private devFee;
    uint256 private totalFee;
    uint256 public feeDenominator = 10000;

    // Buy Fees
    uint256 public burnFeeBuy = 100;
    uint256 public gov1FeeBuy = 100;
    uint256 public gov2FeeBuy = 200;
    uint256 public liquidityFeeBuy = 200;
    uint256 public jackpotFeeBuy = 300;
    uint256 public bonusFeeBuy = 300;
    uint256 public devFeeBuy = 300;
    uint256 public totalFeeBuy = 1500;
    // Sell Fees
    uint256 public burnFeeSell = 100;
    uint256 public gov1FeeSell = 100;
    uint256 public gov2FeeSell = 200;
    uint256 public liquidityFeeSell = 200;
    uint256 public jackpotFeeSell = 300;
    uint256 public bonusFeeSell = 300;
    uint256 public devFeeSell = 300;
    uint256 public totalFeeSell = 1500;

    // Fees receivers
    address private gov1Wallet;
    address private gov2Wallet;
    address private bonusWallet;
    IJackpot public jackpotWallet;
    address private devWallet;

    IERC20 public backToken;
    uint256 public launchedAt;
    uint256 public launchedAtTimestamp;
    bool private initialized;

    ICamelotFactory private immutable factory;
    ICamelotRouter private immutable swapRouter;
    IWETH private immutable WETH;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address private constant ZERO = 0x0000000000000000000000000000000000000000;

    EnumerableSet.AddressSet private _pairs;

    constructor(
        IERC20 _backToken,
        address _factory,
        address _swapRouter,
        address _weth
    ) ERC20("AiFLOKI", "AiFLOKI") {
        uint256 _totalSupply = 100000000000000 * 10**decimals();
        backToken = _backToken;
        canAddLiquidityBeforeLaunch[_msgSender()] = true;
        canAddLiquidityBeforeLaunch[address(this)] = true;
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        factory = ICamelotFactory(_factory);
        swapRouter = ICamelotRouter(_swapRouter);
        WETH = IWETH(_weth);
        _mint(_msgSender(), _totalSupply);
    }

    function initializePair() external onlyOwner {
        require(!initialized, "Already initialized");
        address pair = factory.createPair(address(WETH), address(this));
        _pairs.add(pair);
        initialized = true;
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function transfer(address to, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        return _dogTransfer(_msgSender(), to, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return _dogTransfer(sender, recipient, amount);
    }

    function _dogTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        if (inSwap) {
            _transfer(sender, recipient, amount);
            return true;
        }
        if (!canAddLiquidityBeforeLaunch[sender]) {
            require(launched(), "Trading not open yet");
        }

        bool shouldTakeFee = (!isFeeExempt[sender] &&
            !isFeeExempt[recipient]) && launched();
        uint256 side = 0;
        address user_ = sender;
        address pair_ = recipient;
        // Set Fees
        if (isPair(sender)) {
            buyFees();
            side = 1;
            user_ = recipient;
            pair_ = sender;
            try jackpotWallet.tradeEvent(sender, amount) {} catch {}
        } else if (isPair(recipient)) {
            sellFees();
            side = 2;
        } else {
            shouldTakeFee = false;
        }

        if (shouldSwapBack()) {
            swapBack();
        }

        uint256 amountReceived = shouldTakeFee
            ? takeFee(sender, amount)
            : amount;
        _transfer(sender, recipient, amountReceived);

        if (side > 0) {
            emit Trade(
                user_,
                pair_,
                amount,
                side,
                getCirculatingSupply(),
                block.timestamp
            );
        }
        return true;
    }

    function shouldSwapBack() internal view returns (bool) {
        return
            !inSwap &&
            swapEnabled &&
            launched() &&
            balanceOf(address(this)) > 0 &&
            !isPair(_msgSender());
    }

    function swapBack() internal swapping {
        uint256 taxAmount = balanceOf(address(this));
        _approve(address(this), address(swapRouter), taxAmount);

        uint256 amountDogBurn = (taxAmount * burnFee) / (totalFee);
        uint256 amountDogLp = (taxAmount * liquidityFee) / (totalFee);
        uint256 amountDogBonus = (taxAmount * bonusFee) / (totalFee);
        taxAmount -= amountDogBurn;
        taxAmount -= amountDogLp;
        taxAmount -= amountDogBonus;

        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = address(WETH);
        path[2] = address(backToken);

        bool success = false;
        uint256 balanceBefore = backToken.balanceOf(address(this));
        try
            swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                taxAmount,
                0,
                path,
                address(this),
                address(0),
                block.timestamp
            )
        {
            success = true;
        } catch {
            try
                swapRouter
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        taxAmount,
                        0,
                        path,
                        address(this),
                        block.timestamp
                    )
            {
                success = true;
            } catch {}
        }
        if (!success) {
            return;
        }

        _transfer(address(this), DEAD, amountDogBurn);
        _approve(address(this), address(bonusWallet), amountDogBonus);
        IDogeBonusPool(bonusWallet).injectRewards(amountDogBonus);

        uint256 amountBackToken = backToken.balanceOf(address(this)) -
            balanceBefore;
        uint256 backTokenTotalFee = totalFee -
            burnFee -
            liquidityFee -
            bonusFee;
        uint256 amountBackTokenGov1 = (amountBackToken * gov1Fee) /
            (backTokenTotalFee);
        uint256 amountBackTokenGov2 = (amountBackToken * gov2Fee) /
            (backTokenTotalFee);
        uint256 amountBackTokenJackpot = (amountBackToken * jackpotFee) /
            backTokenTotalFee;
        uint256 amountBackTokenDev = amountBackToken -
            amountBackTokenGov1 -
            amountBackTokenGov2 -
            amountBackTokenJackpot;

        backToken.transfer(gov1Wallet, amountBackTokenGov1);
        backToken.transfer(gov2Wallet, amountBackTokenGov2);
        backToken.transfer(address(jackpotWallet), amountBackTokenJackpot);
        backToken.transfer(devWallet, amountBackTokenDev);

        if (addLiquidityEnabled) {
            _doAddLp();
        }

        emit SwapBack(
            amountDogBurn,
            amountBackTokenGov1,
            amountBackTokenGov2,
            amountDogLp,
            amountBackTokenJackpot,
            amountDogBonus,
            amountBackTokenDev,
            block.timestamp
        );
    }

    function _doAddLp() internal {
        address[] memory pathEth = new address[](2);
        pathEth[0] = address(this);
        pathEth[1] = address(WETH);

        uint256 tokenAmount = balanceOf(address(this));
        uint256 half = tokenAmount / 2;
        if (half < 1000) return;

        uint256 ethAmountBefore = address(this).balance;
        bool success = false;
        try
            swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
                half,
                0,
                pathEth,
                address(this),
                address(0),
                block.timestamp
            )
        {
            success = true;
        } catch {
            try
                swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
                    half,
                    0,
                    pathEth,
                    address(this),
                    block.timestamp
                )
            {
                success = true;
            } catch {}
        }
        if (!success) {
            return;
        }

        uint256 ethAmount = address(this).balance - ethAmountBefore;
        _addLiquidity(half, ethAmount);
    }

    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {
        _approve(address(this), address(swapRouter), tokenAmount);
        try
            swapRouter.addLiquidityETH{value: ethAmount}(
                address(this),
                tokenAmount,
                0,
                0,
                address(0),
                block.timestamp
            )
        {
            emit AddLiquidity(tokenAmount, ethAmount, block.timestamp);
        } catch {}
    }

    function doSwapBack() public onlyOwner {
        swapBack();
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function buyFees() internal {
        burnFee = burnFeeBuy;
        gov1Fee = gov1FeeBuy;
        gov2Fee = gov2FeeBuy;
        liquidityFee = liquidityFeeBuy;
        jackpotFee = jackpotFeeBuy;
        bonusFee = bonusFeeBuy;
        devFee = devFeeBuy;
        totalFee = totalFeeBuy;
    }

    function sellFees() internal {
        burnFee = burnFeeSell;
        gov1Fee = gov1FeeSell;
        gov2Fee = gov2FeeSell;
        liquidityFee = liquidityFeeSell;
        jackpotFee = jackpotFeeSell;
        bonusFee = bonusFeeSell;
        devFee = devFeeSell;
        totalFee = totalFeeSell;
    }

    function takeFee(address sender, uint256 amount)
        internal
        returns (uint256)
    {
        uint256 feeAmount = (amount * totalFee) / feeDenominator;
        _transfer(sender, address(this), feeAmount);
        return amount - feeAmount;
    }

    function rescueToken(address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(
            msg.sender,
            IERC20(tokenAddress).balanceOf(address(this))
        );
    }

    function clearStuckEthBalance() external onlyOwner {
        uint256 amountETH = address(this).balance;
        (bool success, ) = payable(_msgSender()).call{value: amountETH}(
            new bytes(0)
        );
        require(success, "AIDOGE: ETH_TRANSFER_FAILED");
    }

    function clearStuckBalance() external onlyOwner {
        backToken.transfer(_msgSender(), backToken.balanceOf(address(this)));
    }

    function getCirculatingSupply() public view returns (uint256) {
        return totalSupply() - balanceOf(DEAD) - balanceOf(ZERO);
    }

    /*** ADMIN FUNCTIONS ***/
    function launch() public onlyOwner {
        require(launchedAt == 0, "Already launched");
        launchedAt = block.number;
        launchedAtTimestamp = block.timestamp;
    }

    function setBuyFees(
        uint256 _gov1Fee,
        uint256 _gov2Fee,
        uint256 _liquidityFee,
        uint256 _jackpotFee,
        uint256 _bonusFee,
        uint256 _devFee,
        uint256 _burnFee
    ) external onlyOwner {
        gov1FeeBuy = _gov1Fee;
        gov2FeeBuy = _gov2Fee;
        liquidityFeeBuy = _liquidityFee;
        jackpotFeeBuy = _jackpotFee;
        bonusFeeBuy = _bonusFee;
        devFeeBuy = _devFee;
        burnFeeBuy = _burnFee;
        totalFeeBuy =
            _liquidityFee +
            _jackpotFee +
            _bonusFee +
            _devFee +
            _burnFee;
    }

    function setSellFees(
        uint256 _gov1Fee,
        uint256 _gov2Fee,
        uint256 _liquidityFee,
        uint256 _jackpotFee,
        uint256 _bonusFee,
        uint256 _devFee,
        uint256 _burnFee
    ) external onlyOwner {
        gov1FeeSell = _gov1Fee;
        gov2FeeSell = _gov2Fee;
        liquidityFeeSell = _liquidityFee;
        jackpotFeeSell = _jackpotFee;
        bonusFeeSell = _bonusFee;
        devFeeSell = _devFee;
        burnFeeSell = _burnFee;
        totalFeeSell =
            _liquidityFee +
            _jackpotFee +
            _bonusFee +
            _devFee +
            _burnFee;
    }

    function setFeeReceivers(
        address _gov1Wallet,
        address _gov2Wallet,
        address _bonusWallet,
        address _jackpotWallet,
        address _devWallet
    ) external onlyOwner {
        gov1Wallet = _gov1Wallet;
        gov2Wallet = _gov2Wallet;
        bonusWallet = _bonusWallet;
        jackpotWallet = IJackpot(_jackpotWallet);
        devWallet = _devWallet;
        devWallet = _devWallet;
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function setSwapBackSettings(bool _enabled) external onlyOwner {
        swapEnabled = _enabled;
    }

    function setAddLiquidityEnabled(bool _enabled) external onlyOwner {
        addLiquidityEnabled = _enabled;
    }

    function isPair(address account) public view returns (bool) {
        return _pairs.contains(account);
    }

    function addPair(address pair) public onlyOwner returns (bool) {
        require(pair != address(0), "AIDOGE: pair is the zero address");
        return _pairs.add(pair);
    }

    function delPair(address pair) public onlyOwner returns (bool) {
        require(pair != address(0), "AIDOGE: pair is the zero address");
        return _pairs.remove(pair);
    }

    function getMinterLength() public view returns (uint256) {
        return _pairs.length();
    }

    function getPair(uint256 index) public view returns (address) {
        require(index <= _pairs.length() - 1, "AIDOGE: index out of bounds");
        return _pairs.at(index);
    }

    receive() external payable {}
}

