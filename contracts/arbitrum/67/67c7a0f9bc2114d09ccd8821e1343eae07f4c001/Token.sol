// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Context.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./EnumerableSet.sol";
import "./IBonusPool.sol";
import "./IWETH.sol";
import "./IUniswapV2Router01.sol";

interface ICamelotRouter is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        address referrer,
        uint deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        address referrer,
        uint deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        address referrer,
        uint deadline
    ) external;

    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

interface ICamelotFactory {
	event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

contract PEPEARB is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event SwapBack(uint256 burn, uint256 gov, uint256 liquidity, uint256 bonus,uint256 dev, uint timestamp);
    event Trade(address user, address pair, uint256 amount, uint side, uint256 circulatingSupply, uint timestamp);
    event AddLiquidity(uint256 tokenAmount, uint256 ethAmount, uint256 timestamp);

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
    uint256 private govFee;
    uint256 private liquidityFee;
    uint256 private bonusFee;
    uint256 private devFee1;
    uint256 private devFee2;
    uint256 private totalFee;
    uint256 public feeDenominator = 10000;

    // Buy Fees
    uint256 public burnFeeBuy = 200;
    uint256 public govFeeBuy = 300;
    uint256 public liquidityFeeBuy = 350;
    uint256 public bonusFeeBuy = 250;
    uint256 public devFeeBuy1 = 300;
    uint256 public devFeeBuy2 = 100;
    uint256 public totalFeeBuy = 1500;
    // Sell Fees
    uint256 public burnFeeSell = 200;
    uint256 public govFeeSell = 300;
    uint256 public liquidityFeeSell = 350;
    uint256 public bonusFeeSell = 250;
    uint256 public devFeeSell1 = 300;
    uint256 public devFeeSell2 = 100;
    uint256 public totalFeeSell = 1500;

    // Fees receivers
    address private govWallet;
    address private bonusWallet;
    address private devWallet1;
    address private devWallet2;

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
    ) ERC20("PEPEARB", "PEPEARB") {
        uint256 _totalSupply = 200_000_000_000_000_000 * 1e6;
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

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        return _manualTransfer(_msgSender(), to, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return _manualTransfer(sender, recipient, amount);
    }

    function _manualTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        if (inSwap) {
            _transfer(sender, recipient, amount);
            return true;
        }
        if (!canAddLiquidityBeforeLaunch[sender]) {
            require(launched(), "PEPEARB: Trading not open yet");
        }

        bool shouldTakeFee = (!isFeeExempt[sender] && !isFeeExempt[recipient]) && launched();
        uint side = 0;
        address user_ = sender;
        address pair_ = recipient;
        // Set Fees
        if (isPair(sender)) {
            buyFees();
            side = 1;
            user_ = recipient;
            pair_ = sender;
        } else if (isPair(recipient)) {
            sellFees();
            side = 2;
        } else {
            shouldTakeFee = false;
        }

        if (shouldSwapBack()) {
            swapBack();
        }

        uint256 amountReceived = shouldTakeFee ? takeFee(sender, amount) : amount;
        _transfer(sender, recipient, amountReceived);

        if (side > 0) {
            emit Trade(user_, pair_, amount, side, getCirculatingSupply(), block.timestamp);
        }
        return true;
    }

    function shouldSwapBack() internal view returns (bool) {
        return !inSwap && swapEnabled && launched() && balanceOf(address(this)) > 0 && !isPair(_msgSender());
    }

    function swapBack() internal swapping {
        uint256 taxAmount = balanceOf(address(this));
        _approve(address(this), address(swapRouter), taxAmount);

        uint256 amountBurn = (taxAmount * burnFee) / (totalFee);
        uint256 amountLp = (taxAmount * liquidityFee) / (totalFee);
        uint256 amountBonus = (taxAmount * bonusFee) / (totalFee);
        uint256 amountDev1 = (taxAmount * devFee1) / (totalFee);
        uint256 amountDev2 = (taxAmount * devFee2) / (totalFee);
        taxAmount -= amountBurn;
        taxAmount -= amountLp;
        taxAmount -= amountBonus;
        taxAmount -= amountDev1;
        taxAmount -= amountDev2;
        

        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = address(WETH);
        path[2] = address(backToken);


        uint256 ethAmountBefore = address(this).balance;
        _sendETHToDev(amountDev1, amountDev2);
        uint256 devAmount = address(this).balance - ethAmountBefore;


        bool success = false;
        uint256 balanceBefore = backToken.balanceOf(address(this));
         try swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(taxAmount,0,path,address(this),address(0),block.timestamp){
            success = true;
        } catch {
            try swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(taxAmount,0,path,address(this),block.timestamp) {
                success = true;
            } 
            catch {}
        }
        if (!success) {
            return;
        }

        _transfer(address(this), DEAD, amountBurn);
        _approve(address(this), address(bonusWallet), amountBonus);
        IBonusPool(bonusWallet).injectRewards(amountBonus);
        
        uint256 amountBackToken = backToken.balanceOf(address(this)) - balanceBefore;
        uint256 backTokenTotalFee = totalFee - burnFee - liquidityFee - bonusFee;
        uint256 amountBackTokenGov = (amountBackToken * govFee) / (backTokenTotalFee);

        backToken.transfer(govWallet, amountBackTokenGov);

        if (addLiquidityEnabled) {
            _doAddLp(amountLp);
        }
        
        emit SwapBack(amountBurn, amountBackTokenGov, amountLp, amountBonus, devAmount, block.timestamp);
    }

    function _sendETHToDev(uint256 amountDev1, uint256 amountDev2) internal {
        address[] memory pathEth = new address[](2);
        pathEth[0] = address(this);
        pathEth[1] = address(WETH);
        uint256 tokenAmount = amountDev1;

        bool success = false;
        try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount,0, pathEth,devWallet1,address(0),block.timestamp){
            success = true;
        } catch {
            try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount,0, pathEth,devWallet1,block.timestamp){
                success = true;
            } catch {}
        }
       
        if (!success) {
            return;
        }


        tokenAmount = amountDev2;
        success = false;
       try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount,0, pathEth,devWallet2,address(0),block.timestamp){
            success = true;
        } catch {
            try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount,0, pathEth,devWallet2,block.timestamp){
                success = true;
            } catch {}
        }
        if (!success) {
            return;
        }
    }

    function _doAddLp(uint256 amountLP) internal {
        address[] memory pathEth = new address[](2);
        pathEth[0] = address(this);
        pathEth[1] = address(WETH);

        uint256 tokenAmount = amountLP;
        uint256 half = tokenAmount / 2;
        if(half < 1000) return;

        uint256 ethAmountBefore = address(this).balance;
        bool success = false;
        try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(half,0, pathEth,address(this),address(0),block.timestamp){
            success = true;
        } catch {
            try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(half,0, pathEth,address(this),block.timestamp){
                success = true;
            } catch {}
        }

        uint256 ethAmount = address(this).balance - ethAmountBefore;
        _addLiquidity(half, ethAmount);
    }

    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {
        _approve(address(this), address(swapRouter), tokenAmount);
        try swapRouter.addLiquidityETH{value: ethAmount}(address(this), tokenAmount, 0, 0, address(0), block.timestamp) {
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
        govFee = govFeeBuy;
        liquidityFee = liquidityFeeBuy;
        bonusFee = bonusFeeBuy;
        devFee1 = devFeeBuy1;
        devFee2 = devFeeBuy2;
        totalFee = totalFeeBuy;
    }

    function sellFees() internal {
        burnFee = burnFeeSell;
        govFee = govFeeSell;
        liquidityFee = liquidityFeeSell;
        bonusFee = bonusFeeSell;
        devFee1 = devFeeSell1;
        devFee2 = devFeeSell2;
        totalFee = totalFeeSell;
    }

    function takeFee(address sender, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = (amount * totalFee) / feeDenominator;
        _transfer(sender, address(this), feeAmount);
        return amount - feeAmount;
    }

    function rescueToken(address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(msg.sender,IERC20(tokenAddress).balanceOf(address(this)));
    }

    function clearStuckEthBalance() external onlyOwner {
        uint256 amountETH = address(this).balance;
        (bool success, ) = payable(_msgSender()).call{value: amountETH}(new bytes(0));
        require(success, 'PEPEARB: ETH_TRANSFER_FAILED');
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
        uint256 _govFee,
        uint256 _liquidityFee,
        uint256 _bonusFee,
        uint256 _devFee1,
        uint256 _devFee2,
        uint256 _burnFee
    ) external onlyOwner {
        govFeeBuy = _govFee;
        liquidityFeeBuy = _liquidityFee;
        bonusFeeBuy = _bonusFee;
        devFeeBuy1 = _devFee1;
        devFeeBuy2 = _devFee2;
        burnFeeBuy = _burnFee;
        totalFeeBuy = _liquidityFee  + _bonusFee + _devFee1 + _devFee2 + _burnFee + _govFee;
    }

    function setSellFees(
        uint256 _govFee,
        uint256 _liquidityFee,
        uint256 _bonusFee,
        uint256 _devFee1,
        uint256 _devFee2,
        uint256 _burnFee
    ) external onlyOwner {
        govFeeSell = _govFee;
        liquidityFeeSell = _liquidityFee;
        bonusFeeSell = _bonusFee;
        devFeeSell1 = _devFee1;
        devFeeSell2 = _devFee2;
        burnFeeSell = _burnFee;
        totalFeeSell = _liquidityFee  + _bonusFee + _devFee1 + _devFee2 + _burnFee + _govFee;
    }

    function setFeeReceivers(
        address _govWallet,
        address _bonusWallet,
        address _devWallet1,
        address _devWallet2
    ) external onlyOwner {
        govWallet = _govWallet;
        bonusWallet = _bonusWallet;
        devWallet1 = _devWallet1;
        devWallet2 = _devWallet2;
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
        require(pair != address(0), "PEPEARB: pair is the zero address");
        return _pairs.add(pair);
    }

    function delPair(address pair) public onlyOwner returns (bool) {
        require(pair != address(0), "PEPEARB: pair is the zero address");
        return _pairs.remove(pair);
    }

    function getMinterLength() public view returns (uint256) {
        return _pairs.length();
    }

    function getPair(uint256 index) public view returns (address) {
        require(index <= _pairs.length() - 1, "PEPEARB: index out of bounds");
        return _pairs.at(index);
    }

    receive() external payable {}
}
