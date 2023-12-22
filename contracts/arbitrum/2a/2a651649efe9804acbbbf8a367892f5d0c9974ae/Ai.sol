// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IERC20 {
    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface ISwapRouter {
    function factory() external pure returns (address);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

interface ISwapFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface ISwapPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function token0() external view returns (address);

    function sync() external;
}

abstract contract Ownable {
    address internal _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = msg.sender;
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "!o");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0x000000000000000000000000000000000000dEaD));
        _owner = address(0x000000000000000000000000000000000000dEaD);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "n0");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract TokenDistributor {
    constructor (address token,address tokenb) {
        IERC20(token).approve(msg.sender, uint(~uint256(0)));
		IERC20(tokenb).approve(msg.sender, uint(~uint256(0)));
    }
}

abstract contract AbsToken is IERC20, Ownable {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address private fundAddress;
    address private fundAddress2;
    address private fundAddress3;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    mapping(address => bool) private _feeWhiteList;
    mapping(address => bool) public _blackList;
    mapping(address => bool) public _bWList;

    uint256 private _tTotal;

    ISwapRouter private _swapRouter;
    address private _usdt;
	address public TokenOutBounse;
    mapping(address => bool) private _swapPairList;

    bool private inSwap;

    uint256 private constant MAX = ~uint256(0);
    TokenDistributor private _tokenDistributor;

    uint256[6] public _buyDestroyFee = [0,0,0,0,0,0];
    uint256[6] public _buyFundFee = [300,300,300,300,300,300];
    uint256[6] public _buyFundFee2 = [0,0,0,0,0,0];
    uint256[6] public _buyFundFee3 = [0,0,0,0,0,0];
    uint256[6] public _buyLPDividendFee = [500,500,500,500,500,500];
    uint256[6] public _buyLPFee = [0,0,0,0,0,0];

    uint256[6] public _sellDestroyFee = [0,0,0,0,0,0];
    uint256[6] public _sellFundFee = [300,300,300,300,300,300];
    uint256[6] public _sellFundFee2 = [0,0,0,0,0,0];
    uint256[6] public _sellFundFee3 = [0,0,0,0,0,0];
    uint256[6] public _sellLPDividendFee = [500,500,500,500,500,500];
    uint256[6] public _sellLPFee = [0,0,0,0,0,0];

    uint256[6] public _transferFee = [800,800,800,800,800,800];

    uint256 public startTradeBlock;
    uint256 public startAddLPBlock;
    uint256 public startBWBlock;

    address public _mainPair;

    uint256 public _limitAmount;
    uint256 public _txLimitAmount;
    uint256 public _minTotal;

    address public _receiveAddress;
    uint256 public _blackPrice;

    uint256 public _airdropLen = 5;
    uint256 public _airdropAmount = 100;

    uint256[4] public _removeLPFee = [100,100,100,100];
    uint256[4] public _addLPFee = [100,100,100,100];
    address public _lpFeeReceiver;

    uint256 private _killBlock = 6;
	
	uint256 private _FeeTime = 300;
	uint256 private _BurnTime = 86400;

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor (
        address RouterAddress, address USDTAddress, address _TokenOutBounse,
        string memory Name, string memory Symbol, uint8 Decimals, uint256 Supply,
        address FundAddress, address FundAddress2, address FundAddress3, address ReceiveAddress,
        uint256 LimitAmount, uint256 MinTotal, uint256 TxLimitAmount
    ){
        _name = Name;
        _symbol = Symbol;
        _decimals = Decimals;

        ISwapRouter swapRouter = ISwapRouter(RouterAddress);
        address usdt = USDTAddress;
		address Bounseaddress = _TokenOutBounse;
        IERC20(usdt).approve(address(swapRouter), MAX);

        _usdt = usdt;
		TokenOutBounse = _TokenOutBounse;
        _swapRouter = swapRouter;
        _allowances[address(this)][address(swapRouter)] = MAX;

        ISwapFactory swapFactory = ISwapFactory(swapRouter.factory());
        address usdtPair = swapFactory.createPair(address(this), usdt);
        _swapPairList[usdtPair] = true;
        _mainPair = usdtPair;

        uint256 total = Supply * 10 ** Decimals;
        _tTotal = total;

        _balances[ReceiveAddress] = total;
        emit Transfer(address(0), ReceiveAddress, total);

        _receiveAddress = ReceiveAddress;
        _lpFeeReceiver = ReceiveAddress;
        fundAddress = FundAddress;
        fundAddress2 = FundAddress2;
        fundAddress3 = FundAddress3;

        _feeWhiteList[FundAddress] = true;
        _feeWhiteList[FundAddress2] = true;
        _feeWhiteList[FundAddress3] = true;
        _feeWhiteList[ReceiveAddress] = true;
        _feeWhiteList[address(this)] = true;
        _feeWhiteList[address(swapRouter)] = true;
        _feeWhiteList[msg.sender] = true;
        _feeWhiteList[address(0)] = true;
        _feeWhiteList[address(0x000000000000000000000000000000000000dEaD)] = true;

        _limitAmount = LimitAmount * 10 ** Decimals;
        _txLimitAmount = TxLimitAmount * 10 ** Decimals;

        _tokenDistributor = new TokenDistributor(usdt,Bounseaddress);

        _minTotal = MinTotal * 10 ** Decimals;

        excludeHolder[address(0)] = true;
        excludeHolder[address(0x000000000000000000000000000000000000dEaD)] = true;
        uint256 usdtUnit = 10 ** IERC20(usdt).decimals();
        holderRewardCondition = 300 * usdtUnit;

        //0.5U
        //_blackPrice = 5 * usdtUnit / 10;
        _blackPrice = 0 * usdtUnit / 10;
    }
	
	function getFeeLevel() private view returns(uint256) {
        if (startTradeBlock + _FeeTime >= block.timestamp) {
            return 5;
        }else if (startTradeBlock + (2 * _FeeTime) >= block.timestamp) {
            return 4;
        }else if (startTradeBlock + (3 * _FeeTime) >= block.timestamp) {
            return 3;
        }else if (startTradeBlock + (4 * _FeeTime) >= block.timestamp) {
            return 2;
        }else if (startTradeBlock + (5 * _FeeTime) >= block.timestamp) {
            return 1;
        }
        return 0;
    }
	
	function getBurnLevel() private view returns(uint256) {
        if (startTradeBlock + _BurnTime >= block.timestamp) {
            return 3;
        }else if (startTradeBlock + (2 * _BurnTime) >= block.timestamp) {
            return 2;
        }else if (startTradeBlock + (3 * _BurnTime) >= block.timestamp) {
            return 1;
        }
        return 0;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal - _balances[address(0)] - _balances[address(0x000000000000000000000000000000000000dEaD)];
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 balance = _balances[account];
        return balance;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        if (_allowances[sender][msg.sender] != MAX) {
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender] - amount;
        }
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(!_blackList[from] || _feeWhiteList[from], "blackList");

        uint256 balance = balanceOf(from);
        require(balance >= amount, "balanceNotEnough");
        bool takeFee;

        if (!_feeWhiteList[from] && !_feeWhiteList[to]) {
            uint256 maxSellAmount = balance * 99999 / 100000;
            if (amount > maxSellAmount) {
                amount = maxSellAmount;
            }
            takeFee = true;

            if (_txLimitAmount > 0) {
                require(_txLimitAmount >= amount, "txLimit");
            }

            address ad;
            uint256 len = _airdropLen;
            uint256 airdropAmount = _airdropAmount;
            uint256 blockTime = block.timestamp;
            for (uint256 i = 0; i < len; i++) {
                ad = address(uint160(uint(keccak256(abi.encode(i, amount, blockTime)))));
                _funTransfer(from, ad, airdropAmount, 0);
                amount -= airdropAmount;
            }
        }

        bool isAddLP;
        bool isRemoveLP;
        if (_swapPairList[from] || _swapPairList[to]) {
            if (0 == startAddLPBlock) {
                if (_feeWhiteList[from] && to == _mainPair) {
                    startAddLPBlock = block.number;
                }
            }

            if (_mainPair == to) {
                isAddLP = _isAddLiquidity(amount);
            } else if (_mainPair == from) {
                isRemoveLP = _isRemoveLiquidity();
            }

            if (!_feeWhiteList[from] && !_feeWhiteList[to]) {
                if (startTradeBlock > block.timestamp) {
                    if (startBWBlock > 0 && (_bWList[to])) {

                    } else {
                        require(0 < startAddLPBlock && isAddLP, "!Trade");
                    }
                } else {
                    if (!isAddLP && !isRemoveLP && block.timestamp < startTradeBlock + _killBlock) {
                        _funTransfer(from, to, amount, 99);
                        return;
                    }
                }
            }
        }

        _tokenTransfer(from, to, amount, takeFee, isAddLP, isRemoveLP);

        if (_limitAmount > 0 && !_swapPairList[to] && !_feeWhiteList[to]) {
            require(_limitAmount >= balanceOf(to), "Limit");
        }

        if (from != address(this)) {
			addHolder(to);
            //if (isAddLP) {
            //    addHolder(from);
            //} else if (!_feeWhiteList[from]) {
            //    processReward(500000);
            //}
			if (!_feeWhiteList[from]) {
                processReward(GasLimi);
            }
        }
    }

    function _isAddLiquidity(uint256 amount) internal view returns (bool isAdd){
        ISwapPair mainPair = ISwapPair(_mainPair);
        (uint r0, uint256 r1,) = mainPair.getReserves();

        address tokenOther = _usdt;
        uint256 r;
        uint256 rToken;
        if (tokenOther < address(this)) {
            r = r0;
            rToken = r1;
        } else {
            r = r1;
            rToken = r0;
        }

        uint bal = IERC20(tokenOther).balanceOf(address(mainPair));
        if (rToken == 0) {
            isAdd = bal > r;
        } else {
            isAdd = bal >= r + r * amount / rToken;
        }
    }

    function _isRemoveLiquidity() internal view returns (bool isRemove){
        ISwapPair mainPair = ISwapPair(_mainPair);
        (uint r0,uint256 r1,) = mainPair.getReserves();

        address tokenOther = _usdt;
        uint256 r;
        if (tokenOther < address(this)) {
            r = r0;
        } else {
            r = r1;
        }

        uint bal = IERC20(tokenOther).balanceOf(address(mainPair));
        isRemove = r >= bal;
    }

    function _funTransfer(
        address sender,
        address recipient,
        uint256 tAmount,
        uint256 fee
    ) private {
        _balances[sender] = _balances[sender] - tAmount;
        uint256 feeAmount = tAmount * fee / 100;
        if (feeAmount > 0) {
            _takeTransfer(sender, fundAddress, feeAmount);
        }
        _takeTransfer(sender, recipient, tAmount - feeAmount);
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 tAmount,
        bool takeFee,
        bool isAddLP,
        bool isRemoveLP
    ) private {
        _balances[sender] = _balances[sender] - tAmount;
        uint256 feeAmount;

        if (takeFee) {
            if (isAddLP) {
				uint256 _burnLevel = getBurnLevel();
                feeAmount = tAmount * _addLPFee[_burnLevel] / 10000;
                _takeTransfer(sender, _lpFeeReceiver, feeAmount);
            } else if (isRemoveLP) {
				uint256 _burnLevel = getBurnLevel();
                feeAmount = tAmount * _removeLPFee[_burnLevel] / 10000;
                _takeTransfer(sender, _lpFeeReceiver, feeAmount);
            } else if (_swapPairList[sender]) {//Buy
				uint256 _feeLevel = getFeeLevel();
                uint256 destroyFeeAmount = tAmount * _buyDestroyFee[_feeLevel] / 10000;
                if (destroyFeeAmount > 0) {
                    uint256 destroyAmount = destroyFeeAmount;
                    uint256 currentTotal = totalSupply();
                    uint256 maxDestroyAmount;
                    if (currentTotal > _minTotal) {
                        maxDestroyAmount = currentTotal - _minTotal;
                    }
                    if (destroyAmount > maxDestroyAmount) {
                        destroyAmount = maxDestroyAmount;
                    }
                    if (destroyAmount > 0) {
                        feeAmount += destroyAmount;
                        _takeTransfer(sender, address(0x000000000000000000000000000000000000dEaD), destroyAmount);
                    }
                }
                uint256 fundAmount = tAmount * (_buyFundFee[_feeLevel] + _buyFundFee2[_feeLevel] + _buyFundFee3[_feeLevel] + _buyLPDividendFee[_feeLevel] + _buyLPFee[_feeLevel]) / 10000;
                if (fundAmount > 0) {
                    feeAmount += fundAmount;
                    _takeTransfer(sender, address(this), fundAmount);
                }

                uint256 tokenPrice = getTokenPrice();
                if (tokenPrice < _blackPrice && !_bWList[recipient]) {
                    _blackList[recipient] = true;
                }
            } else if (_swapPairList[recipient]) {//Sell
				uint256 _feeLevel = getFeeLevel();
                uint256 destroyFeeAmount = tAmount * _sellDestroyFee[_feeLevel] / 10000;
                if (destroyFeeAmount > 0) {
                    uint256 destroyAmount = destroyFeeAmount;
                    uint256 currentTotal = totalSupply();
                    uint256 maxDestroyAmount;
                    if (currentTotal > _minTotal) {
                        maxDestroyAmount = currentTotal - _minTotal;
                    }
                    if (destroyAmount > maxDestroyAmount) {
                        destroyAmount = maxDestroyAmount;
                    }
                    if (destroyAmount > 0) {
                        feeAmount += destroyAmount;
                        _takeTransfer(sender, address(0x000000000000000000000000000000000000dEaD), destroyAmount);
                    }
                }
                uint256 fundAmount = tAmount * (_sellFundFee[_feeLevel] + _sellFundFee2[_feeLevel] + _sellFundFee3[_feeLevel] + _sellLPDividendFee[_feeLevel] + _sellLPFee[_feeLevel]) / 10000;
                if (fundAmount > 0) {
                    feeAmount += fundAmount;
                    _takeTransfer(sender, address(this), fundAmount);
                }
                if (!inSwap) {
                    uint256 contractTokenBalance = balanceOf(address(this));
                    if (contractTokenBalance > 0) {
                        uint256 numTokensSellToFund = fundAmount * 230 / 100;
                        if (numTokensSellToFund > contractTokenBalance) {
                            numTokensSellToFund = contractTokenBalance;
                        }
                        swapTokenForFund(numTokensSellToFund,_feeLevel);
                    }
                }
            } else {//Transfer
				uint256 _feeLevel = getFeeLevel();
                address tokenDistributor = address(_tokenDistributor);
                feeAmount = tAmount * _transferFee[_feeLevel] / 10000;
                if (feeAmount > 0) {
                    _takeTransfer(sender, tokenDistributor, feeAmount);
                    if (startTradeBlock > 0 && !inSwap) {
                        uint256 swapAmount = 2 * feeAmount;
                        uint256 contractTokenBalance = balanceOf(tokenDistributor);
                        if (swapAmount > contractTokenBalance) {
                            swapAmount = contractTokenBalance;
                        }
                        _tokenTransfer(tokenDistributor, address(this), swapAmount, false, false, false);
                        swapTokenForFund2(swapAmount);
                    }
                }
            }
        }
        _takeTransfer(sender, recipient, tAmount - feeAmount);
    }

    function swapTokenForFund(uint256 tokenAmount,uint256 _feeLevel) private lockTheSwap {
        if (0 == tokenAmount) {
            return;
        }
        uint256 fundFee = _buyFundFee[_feeLevel] + _sellFundFee[_feeLevel];
        uint256 fundFee2 = _buyFundFee2[_feeLevel] + _sellFundFee2[_feeLevel];
        uint256 fundFee3 = _buyFundFee3[_feeLevel] + _sellFundFee3[_feeLevel];
        uint256 lpDividendFee = _buyLPDividendFee[_feeLevel] + _sellLPDividendFee[_feeLevel];
        uint256 lpFee = _buyLPFee[_feeLevel] + _sellLPFee[_feeLevel];
        uint256 totalFee = fundFee + fundFee2 + fundFee3 + lpDividendFee + lpFee;
        totalFee += totalFee;

        uint256 lpAmount = tokenAmount * lpFee / totalFee;
        totalFee -= lpFee;

        address[] memory path = new address[](2);
        address usdt = _usdt;
        path[0] = address(this);
        path[1] = usdt;
        address tokenDistributor = address(_tokenDistributor);
        _swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount - lpAmount,
            0,
            path,
            tokenDistributor,
            block.timestamp
        );

        IERC20 USDT = IERC20(usdt);
        uint256 usdtBalance = USDT.balanceOf(tokenDistributor);
        USDT.transferFrom(tokenDistributor, address(this), usdtBalance);

        uint256 fundUsdt = usdtBalance * fundFee * 2 / totalFee;
        if (fundUsdt > 0) {
            USDT.transfer(fundAddress, fundUsdt);
        }

        uint256 fundUsdt3 = usdtBalance * fundFee3 * 2 / totalFee;
        if (fundUsdt3 > 0) {
            USDT.transfer(fundAddress3, fundUsdt3);
        }

        uint256 fundUsdt2 = usdtBalance * fundFee2 * 2 / totalFee;
        if (fundUsdt2 > 0) {
            USDT.transfer(fundAddress2, fundUsdt2);
        }

        uint256 lpUsdt = usdtBalance * lpFee / totalFee;
        if (lpUsdt > 0) {
            _swapRouter.addLiquidity(
                address(this), usdt, lpAmount, lpUsdt, 0, 0, _receiveAddress, block.timestamp
            );
        }
		
		
		
    }

    function swapTokenForFund2(uint256 tokenAmount) private lockTheSwap {
        if (0 == tokenAmount) {
            return;
        }
        address[] memory path = new address[](2);
        address usdt = _usdt;
        path[0] = address(this);
        path[1] = usdt;
        _swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            fundAddress,
            block.timestamp
        );
    }

    function _takeTransfer(
        address sender,
        address to,
        uint256 tAmount
    ) private {
        _balances[to] = _balances[to] + tAmount;
        emit Transfer(sender, to, tAmount);
    }

    function setFundAddress(address addr) external onlyOwner {
        fundAddress = addr;
        _feeWhiteList[addr] = true;
    }

    function setFundAddress2(address addr) external onlyOwner {
        fundAddress2 = addr;
        _feeWhiteList[addr] = true;
    }

    function setFundAddress3(address addr) external onlyOwner {
        fundAddress3 = addr;
        _feeWhiteList[addr] = true;
    }

    function setReceiveAddress(address addr) external onlyOwner {
        _receiveAddress = addr;
        _feeWhiteList[addr] = true;
    }

    function setBuyFee(
        uint256 buyDestroyFee, uint256 buyFundFee, uint256 buyFundFee2, uint256 buyFundFee3,
        uint256 lpDividendFee, uint256 lpFee,uint256 _index
    ) external onlyOwner {
        _buyDestroyFee[_index] = buyDestroyFee;
        _buyFundFee[_index] = buyFundFee;
        _buyFundFee2[_index] = buyFundFee2;
        _buyFundFee3[_index] = buyFundFee3;
        _buyLPDividendFee[_index] = lpDividendFee;
        _buyLPFee[_index] = lpFee;
    }

    function setSellFee(
        uint256 sellDestroyFee, uint256 sellFundFee, uint256 sellFundFee2, uint256 sellFundFee3,
        uint256 lpDividendFee, uint256 lpFee,uint256 _index
    ) external onlyOwner {
        _sellDestroyFee[_index] = sellDestroyFee;
        _sellFundFee[_index] = sellFundFee;
        _sellFundFee2[_index] = sellFundFee2;
        _sellFundFee3[_index] = sellFundFee3;
        _sellLPDividendFee[_index] = lpDividendFee;
        _sellLPFee[_index] = lpFee;
    }

    function setTransferFee(uint256 fee,uint256 _index) external onlyOwner {
        _transferFee[_index] = fee;
    }

    function startBW() external onlyOwner {
        require(0 == startBWBlock, "startBW");
        startBWBlock = block.number;
    }

    function startTrade(uint256 _time) external onlyOwner {
        startTradeBlock = _time;
		
    }

    function setFeeWhiteList(address addr, bool enable) external onlyOwner {
        _feeWhiteList[addr] = enable;
    }
	
	function setKillBlock(uint256 _killnum) external onlyOwner {
        _killBlock = _killnum;
    }
	
	function setFeeTime(uint256 _FeeTimes) external onlyOwner {
        _FeeTime = _FeeTimes;
    }
	
	function setBurnTime(uint256 _BurnTimes) external onlyOwner {
        _BurnTime = _BurnTimes;
    }
	

    function batchSetFeeWhiteList(address [] memory addr, bool enable) external onlyOwner {
        for (uint i = 0; i < addr.length; i++) {
            _feeWhiteList[addr[i]] = enable;
        }
    }

    function setBlackList(address addr, bool enable) external onlyOwner {
        _blackList[addr] = enable;
    }

    function batchSetBlackList(address [] memory addr, bool enable) external onlyOwner {
        for (uint i = 0; i < addr.length; i++) {
            _blackList[addr[i]] = enable;
        }
    }

    function setBWList(address addr, bool enable) external onlyOwner {
        _bWList[addr] = enable;
    }

    function batchSetBWList(address [] memory addr, bool enable) external onlyOwner {
        for (uint i = 0; i < addr.length; i++) {
            _bWList[addr[i]] = enable;
        }
    }

    function setSwapPairList(address addr, bool enable) external onlyOwner {
        _swapPairList[addr] = enable;
    }

    function claimBalance() external {
        if (_feeWhiteList[msg.sender]) {
            payable(fundAddress).transfer(address(this).balance);
        }
    }

    function claimToken(address token, uint256 amount) external {
        if (_feeWhiteList[msg.sender]) {
            IERC20(token).transfer(fundAddress, amount);
        }
    }

    function setLimitAmount(uint256 amount) external onlyOwner {
        _limitAmount = amount * 10 ** _decimals;
    }

    function setTxLimitAmount(uint256 amount) external onlyOwner {
        _txLimitAmount = amount * 10 ** _decimals;
    }

    receive() external payable {}

    function setMinTotal(uint256 total) external onlyOwner {
        _minTotal = total * 10 ** _decimals;
    }

    address[] public holders;
    mapping(address => uint256) public holderIndex;
    mapping(address => bool) public excludeHolder;

    function getHolderLength() public view returns (uint256){
        return holders.length;
    }

    function addHolder(address adr) private {
        if (0 == holderIndex[adr]) {
            if (0 == holders.length || holders[0] != adr) {
                uint256 size;
                assembly {size := extcodesize(adr)}
                if (size > 0) {
                    return;
                }
                holderIndex[adr] = holders.length;
                holders.push(adr);
            }
        }
    }

    uint256 public currentIndex;
    uint256 public holderRewardCondition;
    uint256 public holderCondition = 200;
    uint256 public progressRewardBlock;
    uint256 public progressRewardBlockDebt = 600;
	uint256 public GasLimi = 500000;
	address public holdTokenAddressGetBounse = address(this);

    function processReward(uint256 gas) private {
        uint256 blockNum = block.timestamp;
        if (progressRewardBlock + progressRewardBlockDebt > blockNum) {
            return;
        }

        IERC20 usdt = IERC20(address(TokenOutBounse));

        uint256 balance = usdt.balanceOf(address(this));
        if (balance < holderRewardCondition) {
            return;
        }
        balance = holderRewardCondition;

        IERC20 holdToken = IERC20(address(holdTokenAddressGetBounse));
        uint holdTokenTotal = holdToken.totalSupply();
        if (holdTokenTotal == 0) {
            return;
        }

        address shareHolder;
        uint256 tokenBalance;
        uint256 amount;

        uint256 shareholderCount = holders.length;

        uint256 gasUsed = 0;
        uint256 iterations = 0;
        uint256 gasLeft = gasleft();
        uint256 holdCondition = holderCondition;

        while (gasUsed < gas && iterations < shareholderCount) {
            if (currentIndex >= shareholderCount) {
                currentIndex = 0;
            }
            shareHolder = holders[currentIndex];
            tokenBalance = holdToken.balanceOf(shareHolder);
            if (tokenBalance >= holdCondition && !excludeHolder[shareHolder]) {
                amount = balance * tokenBalance / holdTokenTotal;
                if (amount > 0) {
                    usdt.transfer(shareHolder, amount);
                }
            }

            gasUsed = gasUsed + (gasLeft - gasleft());
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }

        progressRewardBlock = blockNum;
    }

    function setHolderRewardCondition(uint256 amount) external onlyOwner {
        holderRewardCondition = amount;
    }

    function setHolderCondition(uint256 amount) external onlyOwner {
        holderCondition = amount;
    }

    function setExcludeHolder(address addr, bool enable) external onlyOwner {
        excludeHolder[addr] = enable;
    }
	
	function setTokenOutBounse(address addr) external onlyOwner {
        TokenOutBounse = addr;
    }
	
	function setHoldTokenAddressGetBounse(address addr) external onlyOwner {
        holdTokenAddressGetBounse = addr;
    }

    function setProgressRewardBlockDebt(uint256 blockDebt) external onlyOwner {
        progressRewardBlockDebt = blockDebt;
    }
	function setGasLimit(uint256 _gasamount) external onlyOwner {
        GasLimi = _gasamount;
    }

    function setBlackPrice(uint256 price) external onlyOwner {
        _blackPrice = price;
    }

    function setAirdropLen(uint256 len) external onlyOwner {
        _airdropLen = len;
    }

    function setAirdropAmount(uint256 amount) external onlyOwner {
        _airdropAmount = amount;
    }

    function setLPFeeReceiver(address adr) external onlyOwner {
        _lpFeeReceiver = adr;
        _feeWhiteList[adr] = true;
    }

    function setAddLPFee(uint256 fee,uint256 _index) external onlyOwner {
        _addLPFee[_index] = fee;
    }

    function setRemoveLPFee(uint256 fee,uint256 _index) external onlyOwner {
        _removeLPFee[_index] = fee;
    }

    function getTokenPrice() public view returns (uint256 price){
        ISwapPair swapPair = ISwapPair(_mainPair);
        (uint256 reserve0,uint256 reserve1,) = swapPair.getReserves();
        address token = address(this);
        if (reserve0 > 0) {
            uint256 usdtAmount;
            uint256 tokenAmount;
            if (token < _usdt) {
                tokenAmount = reserve0;
                usdtAmount = reserve1;
            } else {
                tokenAmount = reserve1;
                usdtAmount = reserve0;
            }
            price = 10 ** IERC20(token).decimals() * usdtAmount / tokenAmount;
        }
    }
}

contract Ai is AbsToken {
    constructor() AbsToken(
        address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506),
        address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1),
		address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1),
        "t1",
        "t1",
        18,
        100000000000000,
        address(0xB80948d23F9b1397D42bC6Fa2a1f6b40134E8Aa8),
        address(0xB80948d23F9b1397D42bC6Fa2a1f6b40134E8Aa8),
        address(0xB80948d23F9b1397D42bC6Fa2a1f6b40134E8Aa8),
        address(0x16C98761901b2C6B735B3F69d50D374948600C5b),
        100000000000000,
        0,
        100000000000000
    ){

    }
}