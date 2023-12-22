// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";

import "./IJackpot.sol";
import "./IStakeBonusPool.sol";
import "./ICamelotFactory.sol";
import "./ICamelotRouter.sol";
import "./IWETH.sol";

contract MOMO is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event SwapBack(uint256 burn, uint256 lpAmount, uint256 stakeBonus,  uint256 lpReward,  uint256 dao, uint256 jackpot, uint256 team, uint timestamp);
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
    uint256 private lpFee;
    uint256 private stakeBonusFee;
    uint256 private lpRewardFee;
    uint256 private daoFee;
    uint256 private jackpotFee;
    uint256 private teamFee;
    uint256 private totalFee;
    
    uint256 public feeDenominator = 10000;

    uint256 public burnFeeBuy = 100;
    uint256 public lpFeeBuy = 100;
    uint256 public stakeBonusFeeBuy = 150;
    uint256 public lpRewardFeeBuy = 100;
    uint256 public daoFeeBuy = 200;
    uint256 public jackpotFeeBuy = 300;
    uint256 public teamFeeBuy = 50;
    uint256 public totalFeeBuy = 1000;

    uint256 public burnFeeSell = 100;
    uint256 public lpFeeSell = 100;
    uint256 public stakeBonusFeeSell = 150;
    uint256 public lpRewardFeeSell = 100;
    uint256 public daoFeeSell = 200;
    uint256 public jackpotFeeSell = 300;
    uint256 public teamFeeSell = 50;
    uint256 public totalFeeSell = 1000;


    address private stakeBonusWallet;
    address private lpRewardWallet;
    address private daoWallet;
    address private jackpotWallet;
    address private teamWallet;

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
    ) ERC20("MOMO", "MOMO") {
        uint256 _totalSupply = 21_000_000_000_000_000 * 1e6;
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
        require(!initialized, "Already initialized!");
        address pair = factory.createPair(address(WETH), address(this));
        _pairs.add(pair);
        initialized = true;
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        return _doTransfer(_msgSender(), to, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return _doTransfer(sender, recipient, amount);
    }

    function _doTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        if (inSwap) {
            _transfer(sender, recipient, amount);
            return true;
        }
        if (!canAddLiquidityBeforeLaunch[sender]) {
            require(launched(), "Trading not open yet!");
        }

        bool shouldTakeFee = (!isFeeExempt[sender] && !isFeeExempt[recipient]) && launched();
        uint side = 0;
        address user_ = sender;
        address pair_ = recipient;
     
        if (isPair(sender)) {
            buyFees();
            side = 1;
            user_ = recipient;
            pair_ = sender;
            try IJackpot(jackpotWallet).trade(sender, amount) {} catch {}
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
        uint256 amountLp = (taxAmount * lpFee) / (totalFee);
        uint256 amountStakeBonus = (taxAmount * stakeBonusFee) / (totalFee);
        taxAmount -= amountBurn;
        taxAmount -= amountLp;
        taxAmount -= amountStakeBonus;
        
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = address(WETH);
        path[2] = address(backToken);

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
        _approve(address(this), address(stakeBonusWallet), amountStakeBonus);
        IStakeBonusPool(stakeBonusWallet).addBonus(amountStakeBonus);
        
        uint256 amountBackToken = backToken.balanceOf(address(this)) - balanceBefore;
        uint256 backTokenTotalFee = totalFee - burnFee - lpFee - stakeBonusFee;

        uint256 amountBackTokenLpReward = (amountBackToken * lpRewardFee) / (backTokenTotalFee);
        uint256 amountBackTokenDao = (amountBackToken * daoFee) / (backTokenTotalFee);
        uint256 amountBackTokenJackpot = (amountBackToken * jackpotFee) / backTokenTotalFee;
        uint256 amountBackTokenTeam = amountBackToken - amountBackTokenLpReward - amountBackTokenDao - amountBackTokenJackpot;

        backToken.transfer(lpRewardWallet, amountBackTokenLpReward);
        backToken.transfer(daoWallet, amountBackTokenDao);
        backToken.transfer(jackpotWallet, amountBackTokenJackpot);
        backToken.transfer(teamWallet, amountBackTokenTeam);

        if (addLiquidityEnabled) {
            _doAddLp();
        }
        
        emit SwapBack(amountBurn, amountLp, amountStakeBonus, amountBackTokenLpReward, amountBackTokenDao, amountBackTokenJackpot, amountBackTokenTeam, block.timestamp);

    }

    function _doAddLp() internal {
        address[] memory pathEth = new address[](2);
        pathEth[0] = address(this);
        pathEth[1] = address(WETH);

        uint256 tokenAmount = balanceOf(address(this));
        uint256 half = tokenAmount / 2;
        if(half < 1000) return;

        uint256 ethAmountBefore = address(this).balance;
        bool success = false;
        try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(half, 0, pathEth, address(this), address(0), block.timestamp){
            success = true;
        } catch {
            try swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(half, 0, pathEth, address(this), block.timestamp){
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
        burnFee         = burnFeeBuy;
        lpFee           = lpFeeBuy;
        stakeBonusFee   = stakeBonusFeeBuy;
        lpRewardFee     = lpRewardFeeBuy;
        daoFee          = daoFeeBuy;
        jackpotFee      = jackpotFeeBuy;
        teamFee         = teamFeeBuy;
        totalFee        = totalFeeBuy;
    }

    function sellFees() internal {
        burnFee         = burnFeeSell;
        lpFee           = lpFeeSell;
        stakeBonusFee   = stakeBonusFeeSell;
        lpRewardFee     = lpRewardFeeSell;
        daoFee          = daoFeeSell;
        jackpotFee      = jackpotFeeSell;
        teamFee         = teamFeeSell;
        totalFee        = totalFeeSell;
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
        require(success, 'MOMO: ETH_TRANSFER_FAILED');
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
        uint256 _burnFee,
        uint256 _lpFee,
        uint256 _stakeBonusFee,
        uint256 _lpRewardFee,
        uint256 _daoFee,
        uint256 _jackpotFee,
        uint256 _teamFee
    ) external onlyOwner {
        burnFeeBuy          = _burnFee;
        lpFeeBuy            = _lpFee;
        stakeBonusFeeBuy    = _stakeBonusFee;
        lpRewardFeeBuy      = _lpRewardFee;
        daoFeeBuy           = _daoFee;
        jackpotFeeBuy       = _jackpotFee;
        teamFeeBuy          = _teamFee;
        totalFeeBuy         = _burnFee + _lpFee + _stakeBonusFee + _lpRewardFee + _daoFee + _jackpotFee + _teamFee;
    }

    function setSellFees(
        uint256 _burnFee,
        uint256 _lpFee,
        uint256 _stakeBonusFee,
        uint256 _lpRewardFee,
        uint256 _daoFee,
        uint256 _jackpotFee,
        uint256 _teamFee
    ) external onlyOwner {
        burnFeeSell         = _burnFee;
        lpFeeSell           = _lpFee;
        stakeBonusFeeSell   = _stakeBonusFee;
        lpRewardFeeSell     = _lpRewardFee;
        daoFeeSell          = _daoFee;
        jackpotFeeSell      = _jackpotFee;
        teamFeeSell         = _teamFee;
        totalFeeSell        = _burnFee + _lpFee + _stakeBonusFee + _lpRewardFee + _daoFee + _jackpotFee + _teamFee;
    }

    function setFeeReceivers(
        address _stakeBonusWallet,
        address _lpRewardWallet,
        address _daoWallet,
        address _jackpotWallet,
        address _teamWallet
    ) external onlyOwner {
        stakeBonusWallet = _stakeBonusWallet;
        lpRewardWallet = _lpRewardWallet;
        daoWallet = _daoWallet;
        jackpotWallet = _jackpotWallet;
        teamWallet = _teamWallet;
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
        require(pair != address(0), "MOMO: pair is the zero address");
        return _pairs.add(pair);
    }

    function delPair(address pair) public onlyOwner returns (bool) {
        require(pair != address(0), "MOMO: pair is the zero address");
        return _pairs.remove(pair);
    }

    function getMinterLength() public view returns (uint256) {
        return _pairs.length();
    }

    function getPair(uint256 index) public view returns (address) {
        require(index <= _pairs.length() - 1, "MOMO: index out of bounds");
        return _pairs.at(index);
    }

    receive() external payable {}
}
