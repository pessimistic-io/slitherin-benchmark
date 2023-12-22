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

interface IRouter is IUniswapV2Router01 {
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

interface IFactory {
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

contract Token is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event SwapBack(uint256 nftHolder,uint256 dev, uint timestamp);
    event Trade(address user, address pair, uint256 amount, uint side, uint timestamp);
    event AddLiquidity(uint256 tokenAmount, uint256 ethAmount, uint256 timestamp);

    bool public swapEnabled = true;

    bool public inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public canAddLiquidityBeforeLaunch;

    uint256 public maxPerTx;
    uint256 private devFee;
    uint256 private nftHolderFee;
    uint256 private totalFee;
    uint256 public feeDenominator = 10000;

    // Buy Fees
    uint256 public devFeeBuy = 300;
    uint256 public nftHolderFeeBuy = 200;
    uint256 public totalFeeBuy = 500;
    // Sell Fees
    uint256 public devFeeSell = 300;
    uint256 public nftHolderFeeSell = 200;
    uint256 public totalFeeSell = 500;

    // Fees receivers
    address private devWallet;
    address private nftHolderWallet;

    uint256 public launchedAt;
    uint256 public launchedAtTimestamp;
    bool private initialized;

    IFactory private immutable factory;
    IRouter private immutable swapRouter;
    IWETH private immutable WETH;

    EnumerableSet.AddressSet private _pairs;

    constructor(
        address _factory,
        address _swapRouter,
        address _weth,
        uint256 _maxPerTx
    ) ERC20("PEPE CIVIL WAR", "PCW") {
        uint256 _totalSupply = 1_000_000_000_000 * 1e6;
        canAddLiquidityBeforeLaunch[_msgSender()] = true;
        canAddLiquidityBeforeLaunch[address(this)] = true;
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        factory = IFactory(_factory);
        swapRouter = IRouter(_swapRouter);
        WETH = IWETH(_weth);
        maxPerTx = _maxPerTx;
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
            require(launched(), "PCW: Trading not open yet");
        }

        bool shouldTakeFee = (!isFeeExempt[sender] && !isFeeExempt[recipient]) && launched();
        uint side = 0;
        address user_ = sender;
        address pair_ = recipient;
        // Set Fees
        if (isPair(sender)) {
            if(sender != owner() || maxPerTx != 0){
                require(amount <= maxPerTx,"PCW: Amount cannot exceed the limit");
            }
            buyFees();
            side = 1;
            user_ = recipient;
            pair_ = sender;
        } else if (isPair(recipient)) {
            if(sender != owner() || maxPerTx != 0){
                require(amount <= maxPerTx,"PCW: Amount cannot exceed the limit");
            }
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
            emit Trade(user_, pair_, amount, side, block.timestamp);
        }
        return true;
    }

    function shouldSwapBack() internal view returns (bool) {
        return !inSwap && swapEnabled && launched() && balanceOf(address(this)) > 0 && !isPair(_msgSender());
    }

    function swapBack() internal swapping {
        uint256 taxAmount = balanceOf(address(this));
        _approve(address(this), address(swapRouter), taxAmount);

        uint256 amountDev = (taxAmount * devFee) / (totalFee);
        uint256 amountNFTHolder = (taxAmount * nftHolderFee) / (totalFee);

        uint256 devAmountBefore = devWallet.balance;
        uint256 nftHolderAmountBefore = nftHolderWallet.balance;
        bool success = _sendETH(amountDev, amountNFTHolder);
        if (!success) {
            return;
        }
        uint256 devAmountAfter = devWallet.balance;
        uint256 nftHolderAmountAfter = nftHolderWallet.balance;
        uint256 devAmount = devAmountAfter - devAmountBefore;
        uint256 nftHolderAmount = nftHolderAmountAfter - nftHolderAmountBefore;
        
        
        emit SwapBack(nftHolderAmount, devAmount, block.timestamp);
    }

    function _sendETH(uint256 amountDev, uint256 amountNFTHolder) internal returns(bool) {
        address[] memory pathEth = new address[](2);
        pathEth[0] = address(this);
        pathEth[1] = address(WETH);
        uint256 tokenAmount = amountDev;

        bool success = false;
        try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount,0, pathEth,devWallet,address(0),block.timestamp){
            success = true;
        } catch {
            try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount,0, pathEth,devWallet,block.timestamp){
                success = true;
            } catch {}
        }
       
        if (!success) {
            return false;
        }


        tokenAmount = amountNFTHolder;
        success = false;
       try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount,0, pathEth,nftHolderWallet,address(0),block.timestamp){
            success = true;
        } catch {
            try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount,0, pathEth,nftHolderWallet,block.timestamp){
                success = true;
            } catch {}
        }
        if (!success) {
            return false;
        }
        return true;
    }


    function doSwapBack() public onlyOwner {
        swapBack();
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function buyFees() internal {
        devFee = devFeeBuy;
        nftHolderFee = nftHolderFeeBuy;
        totalFee = totalFeeBuy;
    }

    function sellFees() internal {
        devFee = devFeeSell;
        nftHolderFee = nftHolderFeeSell;
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
        require(success, 'PCW: ETH_TRANSFER_FAILED');
    }

    /*** ADMIN FUNCTIONS ***/
    function launch() public onlyOwner {
        require(launchedAt == 0, "Already launched");
        launchedAt = block.number;
        launchedAtTimestamp = block.timestamp;
    }

    function setBuyFees(
        uint256 _devFee,
        uint256 _nftHolderFee
    ) external onlyOwner {
        devFeeBuy = _devFee;
        nftHolderFeeBuy = _nftHolderFee;
        totalFeeBuy = _devFee + _nftHolderFee;
    }

    function setSellFees(
        uint256 _devFee,
        uint256 _nftHolderFee
    ) external onlyOwner {
        devFeeSell = _devFee;
        nftHolderFeeSell = _nftHolderFee;
        totalFeeSell = _devFee + _nftHolderFee;
    }

    function setFeeReceivers(
        address _devWallet,
        address _nftHolderWallet
    ) external onlyOwner {
        devWallet = _devWallet;
        nftHolderWallet = _nftHolderWallet;
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function setSwapBackSettings(bool _enabled) external onlyOwner {
        swapEnabled = _enabled;
    }

    function setMaxPerTx(uint256 amount) external onlyOwner {
        maxPerTx = amount;
    }

    function isPair(address account) public view returns (bool) {
        return _pairs.contains(account);
    }

    function addPair(address pair) public onlyOwner returns (bool) {
        require(pair != address(0), "PCW: pair is the zero address");
        return _pairs.add(pair);
    }

    function delPair(address pair) public onlyOwner returns (bool) {
        require(pair != address(0), "PCW: pair is the zero address");
        return _pairs.remove(pair);
    }

    function getMinterLength() public view returns (uint256) {
        return _pairs.length();
    }

    function getPair(uint256 index) public view returns (address) {
        require(index <= _pairs.length() - 1, "PCW: index out of bounds");
        return _pairs.at(index);
    }

    receive() external payable {}
}
