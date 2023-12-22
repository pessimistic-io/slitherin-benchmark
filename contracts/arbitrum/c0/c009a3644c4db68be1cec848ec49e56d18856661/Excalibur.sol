// SPDX-License-Identifier: MIT
//                                                                o .,<>., o
//                                                                |\/\/\/\/|
//                                                                '========'
//                                                                (_ SSSSSSs
//                                                                )a'`SSSSSs
//                                                               /_   SSSSSS
//                                                               .=## SSSSS
//                                                               .####  SSSSs
//                                                               ###::::SSSSS
//                                                              .;:::""""SSS
//                                                             .:;:'  . .  \\
//                                                            .::/  '     .'|
//                                                           .::( .         |
//                                                           :::)           \
//                                                           /\(            /
//                                                          /)            ( |
//                                                        .'  \  .       ./ /
//                                                     _-'    |\  .        |
//                                   _..--..   .  /"---\      | ` |      . |
//           -=====================,' _     \=(*#(7.#####()   |  `/_..   , (
//                       _.-''``';'-''-) ,.  \ '  '+/// |   .'/   \  ``-.) \
//                     ,'  _.-  ((    `-'  `._\    `` \_/_.'  )    /`-._  ) |
//                   ,'\ ,'  _.'.`:-.    \.-'                 /   <_L   )"  |
//                 _/   `._,' ,')`;  `-'`'                    |     L  /    /
//                / `.   ,' ,|_/ / \                          (    <_-'     \
//                \ / `./  '  / /,' \                        /|`         `. |
//                )\   /`._   ,'`._.-\                       |)            \'
//               /  `.'    )-'.-,' )__)                      |\            `|
//              : /`. `.._(--.`':`':/ \                      ) \             \
//              |::::\     ,'/::;-))  /                      ( )`.            |
//              ||:::::  . .::':  :`-(                       |/    .          |
//              ||::::|  . :|  |==[]=:                       .        -       \
//              |||:::|  : ||  :  |  |                      /\           `     |
//  ___ ___     '|;:::|  | |'   \=[]=|                     /  \                \
// |   /_  ||``|||:::::  | ;    | |  |                     \_.'\_               `-.
// :   \_``[]--[]|::::'\_;'     )-'..`._                 .-'\``:: ` .              \
//  \___.>`''-.||:.__,'     SSt |_______`>              <_____:::.         . . \  _/
//                                                            `+a:f:......jrei'''
// https://arthurian.finance/
// https://t.me/ArthurianFinance

pragma solidity 0.8.4;
import "./IERC20.sol";
import "./ERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

 library SafeMathInt {
    int256 private constant MIN_INT256 = int256(1) << 255;
    int256 private constant MAX_INT256 = ~(int256(1) << 255);

    function mul(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a * b;

        require(c != MIN_INT256 || (a & MIN_INT256) != (b & MIN_INT256), "mul: invalid with MIN_INT256");
        require((b == 0) || (c / b == a), "mul: combi values invalid");
        return c;
    }

    function div(int256 a, int256 b) internal pure returns (int256) {
        require(b != -1 || a != MIN_INT256, "div: b == 1 or a == MIN_INT256");
        return a / b;
    }

    function sub(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a - b;
        require((b >= 0 && c <= a) || (b < 0 && c > a), "sub: combi values invalid");
        return c;

    }

    function add(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a + b;
        require((b >= 0 && c >= a) || (b < 0 && c < a), "add: combi values invalid");
        return c;
    }

    function abs(int256 a) internal pure returns (int256) {
        require(a != MIN_INT256, "abs: a equal MIN INT256");
        return a < 0 ? -a : a;
    }
}

interface InterfaceLP {
    function sync() external;
}

abstract contract ERC20Detailed is IERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint8 _tokenDecimals
    ) {
        _name = _tokenName;
        _symbol = _tokenSymbol;
        _decimals = _tokenDecimals;
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
}

interface IDEXRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

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
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

contract Arthurian is ERC20Detailed, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMathInt for int256;

    bool public initialDistributionFinished = false;
    bool public swapEnabled = true;
    bool public autoRebase = false;
    bool public isLiquidityInETH = true;

    uint256 public rewardYield = 3958125;
    uint256 public rewardYieldDenominator = 10000000000;

    uint256 public rebaseFrequency = 1800;
    uint256 public nextRebase = block.timestamp + 31536000;

    mapping(address => bool) _isFeeExempt;
    address[] public _markerPairs;
    mapping(address => bool) public automatedMarketMakerPairs;

    uint256 public constant MAX_FEE_RATE = 18;
    uint256 public constant MAX_FEE_BUY = 13;
    uint256 public constant MAX_FEE_SELL = 18;
    uint256 private constant MAX_REBASE_FREQUENCY = 1800;
    uint256 private constant DECIMALS = 18;
    uint256 private constant MAX_UINT256 = ~uint256(0);
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY =
        23 * 10**8 * 10**DECIMALS;
    uint256 private constant TOTAL_GONS =
        MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);
    uint256 private constant MAX_SUPPLY = ~uint128(0);

    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;

    address public liquidityReceiver =
        0x9ADd0969b4D473d4E836f960B1FCb47002e09E58;
    address public treasuryReceiver =
        0x1d6eA26D55c15BF9AF1E5863E4930eb30D619200;
    address public riskFreeValueReceiver =
        0xC0268211FFEf948cF6f5cd1d98B68568c58f94b7;
    
    address public UsdcToken = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; //mainnet

    IDEXRouter public router;
    address public pair;

    uint256 public liquidityFee = 5;
    uint256 public treasuryFee = 5;
    uint256 public buyFeeRFV = 3;
    uint256 public sellFeeTreasuryAdded = 5;
    uint256 public totalBuyFee = liquidityFee.add(treasuryFee).add(buyFeeRFV);
    uint256 public totalSellFee =
        totalBuyFee.add(sellFeeTreasuryAdded);
    uint256 public feeDenominator = 100;

    uint256 targetLiquidity = 50;
    uint256 targetLiquidityDenominator = 100;

    bool inSwap;

    modifier swapping() {
        require (inSwap == false, "ReentrancyGuard: reentrant call");
        inSwap = true;
        _;
        inSwap = false;
    }

    modifier validRecipient(address to) {
        require(to != address(0x0), "Recipient zero address");
        _;
    }

    uint256 private _totalSupply;
    uint256 private _gonsPerFragment;
    uint256 private gonSwapThreshold = TOTAL_GONS  / 1000;

    mapping(address => uint256) private _gonBalances;
    mapping(address => mapping(address => uint256)) private _allowedFragments;

    constructor() ERC20Detailed("Arthurian", "KING", uint8(DECIMALS))
    {
        router = IDEXRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506); // sushi 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
        
        pair = IDEXFactory(router.factory()).createPair(
            address(this),
            router.WETH()
        );
        address pairUsdc = IDEXFactory(router.factory()).createPair(
            address(this),
            UsdcToken
        );

        _allowedFragments[address(this)][address(router)] = type(uint256).max;
        _allowedFragments[address(this)][pair] = type(uint256).max;
        _allowedFragments[address(this)][address(this)] = type(uint256).max;
        _allowedFragments[address(this)][pairUsdc] = type(uint256).max;

        setAutomatedMarketMakerPair(pair, true);
        setAutomatedMarketMakerPair(pairUsdc, true);

        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonBalances[msg.sender] = TOTAL_GONS;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        _isFeeExempt[treasuryReceiver] = true;
        _isFeeExempt[riskFreeValueReceiver] = true;
        _isFeeExempt[address(this)] = true;
        _isFeeExempt[msg.sender] = true;

        IERC20(UsdcToken).approve(address(router), type(uint256).max);
        IERC20(UsdcToken).approve(address(pairUsdc), type(uint256).max);
        IERC20(UsdcToken).approve(address(this), type(uint256).max);

        emit Transfer(address(0x0), msg.sender, _totalSupply);
    }

    receive() external payable {}

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function allowance(address owner_, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowedFragments[owner_][spender];
    }

    function balanceOf(address who) public view override returns (uint256) {
        return _gonBalances[who].div(_gonsPerFragment);
    }

    function checkFeeExempt(address _addr) external view returns (bool) {
        return _isFeeExempt[_addr];
    }

    function checkSwapThreshold() external view returns (uint256) {
        return gonSwapThreshold.div(_gonsPerFragment);
    }

    function shouldRebase() internal view returns (bool) {
        return nextRebase <= block.timestamp;
    }

    function shouldTakeFee(address from, address to)
        internal
        view
        returns (bool)
    {
        if (_isFeeExempt[from] || _isFeeExempt[to]) {
            return false;
        } else {
            return (automatedMarketMakerPairs[from] ||
                automatedMarketMakerPairs[to]);
        }
    }

    function shouldSwapBack() internal view returns (bool) {
        return
            !automatedMarketMakerPairs[msg.sender] &&
            !inSwap &&
            swapEnabled &&
            totalBuyFee.add(totalSellFee) > 0 &&
            _gonBalances[address(this)] >= gonSwapThreshold;
    }

    function getCirculatingSupply() public view returns (uint256) {
        return
            (TOTAL_GONS.sub(_gonBalances[DEAD]).sub(_gonBalances[ZERO])).div(
                _gonsPerFragment
            );
    }

    function getLiquidityBacking(uint256 accuracy)
        public
        view
        returns (uint256)
    {
        uint256 liquidityBalance = 0;
        for (uint256 i = 0; i < _markerPairs.length; i++) {
            liquidityBalance.add(balanceOf(_markerPairs[i]).div(10**9));
        }
        return
            accuracy.mul(liquidityBalance.mul(2)).div(
                getCirculatingSupply().div(10**9)
            );
    }

    function isOverLiquified(uint256 target, uint256 accuracy)
        public
        view
        returns (bool)
    {
        return getLiquidityBacking(accuracy) > target;
    }

    function manualSync() public {
        for (uint256 i = 0; i < _markerPairs.length; i++) {
            InterfaceLP(_markerPairs[i]).sync();
        }
    }

    function transfer(address to, uint256 value)
        external
        override
        validRecipient(to)
        returns (bool)
    {
        _transferFrom(msg.sender, to, value);
        return true;
    }

    function _basicTransfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        uint256 gonAmount = amount.mul(_gonsPerFragment);
        _gonBalances[from] = _gonBalances[from].sub(gonAmount);
        _gonBalances[to] = _gonBalances[to].add(gonAmount);

        emit Transfer(from, to, amount);

        return true;
    }

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        bool excludedAccount = _isFeeExempt[sender] || _isFeeExempt[recipient];

        require(
            initialDistributionFinished || excludedAccount,
            "Trading not started"
        );

        if (inSwap) {
            return _basicTransfer(sender, recipient, amount);
        }

        uint256 gonAmount = amount.mul(_gonsPerFragment);

        if (shouldSwapBack()) {
            swapBack();
        }

        _gonBalances[sender] = _gonBalances[sender].sub(gonAmount);

        uint256 gonAmountReceived = shouldTakeFee(sender, recipient)
            ? takeFee(sender, recipient, gonAmount)
            : gonAmount;
        _gonBalances[recipient] = _gonBalances[recipient].add(
            gonAmountReceived
        );

        emit Transfer(
            sender,
            recipient,
            gonAmountReceived.div(_gonsPerFragment)
        );

        if (shouldRebase() && autoRebase) {
            _rebase();

            if (
                !automatedMarketMakerPairs[sender] &&
                !automatedMarketMakerPairs[recipient]
            ) {
                manualSync();
            }
        }

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override validRecipient(to) returns (bool) {
        if (_allowedFragments[from][msg.sender] != type(uint256).max) {
            _allowedFragments[from][msg.sender] = _allowedFragments[from][
                msg.sender
            ].sub(value, "Insufficient Allowance");
        }

        _transferFrom(from, to, value);
        return true;
    }

    function _swapAndLiquify(uint256 contractTokenBalance) private {
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        if (isLiquidityInETH) {
            uint256 initialBalance = address(this).balance;

            _swapTokensForETH(half, address(this));

            uint256 newBalance = address(this).balance.sub(initialBalance);

            _addLiquidity(otherHalf, newBalance);

            emit SwapAndLiquify(half, newBalance, otherHalf);
        } else {
            uint256 initialBalance = IERC20(UsdcToken).balanceOf(address(this));

            _swapTokensForUsdc(half, address(this));

            uint256 newBalance = IERC20(UsdcToken).balanceOf(address(this)).sub(
                initialBalance
            );

            _addLiquidityUsdc(otherHalf, newBalance);

            emit SwapAndLiquifyUsdc(half, newBalance, otherHalf);
        }
    }

    function _addLiquidity(uint256 tokenAmount, uint256 ETHAmount) private {
        router.addLiquidityETH{value: ETHAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            liquidityReceiver,
            block.timestamp
        );
    }

    function _addLiquidityUsdc(uint256 tokenAmount, uint256 UsdcAmount)
        private
    {
        router.addLiquidity(
            address(this),
            UsdcToken,
            tokenAmount,
            UsdcAmount,
            0,
            0,
            liquidityReceiver,
            block.timestamp
        );
    }

    function _swapTokensForETH(uint256 tokenAmount, address receiver) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            receiver,
            block.timestamp
        );
    }

    function _swapTokensForUsdc(uint256 tokenAmount, address receiver) private {
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = router.WETH();
        path[2] = UsdcToken;

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            receiver,
            block.timestamp
        );
    }

    function swapBack() internal swapping {
        uint256 realTotalFee = totalBuyFee.add(totalSellFee);

        uint256 dynamicLiquidityFee = isOverLiquified(
            targetLiquidity,
            targetLiquidityDenominator
        )
            ? 0
            : liquidityFee;
        uint256 contractTokenBalance = _gonBalances[address(this)].div(
            _gonsPerFragment
        );

        uint256 amountToLiquify = contractTokenBalance
            .mul(dynamicLiquidityFee.mul(2))
            .div(realTotalFee);
        uint256 amountToRFV = contractTokenBalance
            .mul(buyFeeRFV.mul(2))
            .div(realTotalFee);
        uint256 amountToTreasury = contractTokenBalance
            .sub(amountToLiquify)
            .sub(amountToRFV);

        if (amountToLiquify > 0) {
            _swapAndLiquify(amountToLiquify);
        }

        if (amountToRFV > 0) {
            _swapTokensForETH(amountToRFV, riskFreeValueReceiver);
        }

        if (amountToTreasury > 0) {
            _swapTokensForETH(amountToTreasury, treasuryReceiver);
        }

        emit SwapBack(
            contractTokenBalance,
            amountToLiquify,
            amountToRFV,
            amountToTreasury
        );
    }

    function takeFee(
        address sender,
        address recipient,
        uint256 gonAmount
    ) internal returns (uint256) {
        uint256 _realFee = totalBuyFee;
        if (automatedMarketMakerPairs[recipient]) _realFee = totalSellFee;

        uint256 feeAmount = gonAmount.mul(_realFee).div(feeDenominator);

        _gonBalances[address(this)] = _gonBalances[address(this)].add(
            feeAmount
        );
        emit Transfer(sender, address(this), feeAmount.div(_gonsPerFragment));

        return gonAmount.sub(feeAmount);
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        returns (bool)
    {
        uint256 oldValue = _allowedFragments[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedFragments[msg.sender][spender] = 0;
        } else {
            _allowedFragments[msg.sender][spender] = oldValue.sub(
                subtractedValue
            );
        }
        emit Approval(
            msg.sender,
            spender,
            _allowedFragments[msg.sender][spender]
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        external
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = _allowedFragments[msg.sender][
            spender
        ].add(addedValue);
        emit Approval(
            msg.sender,
            spender,
            _allowedFragments[msg.sender][spender]
        );
        return true;
    }

    function approve(address spender, uint256 value)
        external
        override
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function _rebase() private {
        if (!inSwap) {
            //uint256 circulatingSupply = getCirculatingSupply();
            int256 supplyDelta = int256(
                _totalSupply.mul(rewardYield).div(rewardYieldDenominator)
            );

            coreRebase(supplyDelta);
        }
    }

    function coreRebase(int256 supplyDelta) private returns (uint256) {
        uint256 epoch = block.timestamp;

        if (supplyDelta == 0) {
            emit LogRebase(epoch, _totalSupply);
            return _totalSupply;
        }

        if (supplyDelta < 0) {
            _totalSupply = _totalSupply.sub(uint256(-supplyDelta));
        } else {
            _totalSupply = _totalSupply.add(uint256(supplyDelta));
        }

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        nextRebase = epoch + rebaseFrequency;

        emit LogRebase(epoch, _totalSupply);
        return _totalSupply;
    }

    function manualRebase() external  nonReentrant{
        require(!inSwap, "Try again");
        require(nextRebase <= block.timestamp, "Not in time");

        //uint256 circulatingSupply = getCirculatingSupply();
        int256 supplyDelta = int256(
            _totalSupply.mul(rewardYield).div(rewardYieldDenominator)
        );

        coreRebase(supplyDelta);
        manualSync();
        emit ManualRebase(supplyDelta);
    }

    function setAutomatedMarketMakerPair(address _pair, bool _value)
        public
        onlyOwner
    {
        require(
            automatedMarketMakerPairs[_pair] != _value,
            "Value already set"
        );

        automatedMarketMakerPairs[_pair] = _value;

        if (_value) {
            _markerPairs.push(_pair);
        } else {
            require(_markerPairs.length > 1, "Required 1 pair");
            for (uint256 i = 0; i < _markerPairs.length; i++) {
                if (_markerPairs[i] == _pair) {
                    _markerPairs[i] = _markerPairs[_markerPairs.length - 1];
                    _markerPairs.pop();
                    break;
                }
            }
        }

        emit SetAutomatedMarketMakerPair(_pair, _value);
    }

    function setInitialDistributionFinished(bool _value) external onlyOwner {
        require(initialDistributionFinished != _value, "Not changed");
        initialDistributionFinished = _value;
        emit SetInitialDistributionFinished(_value);
    }

    function setFeeExempt(address _addr, bool _value) external onlyOwner {
        require(_isFeeExempt[_addr] != _value, "Not changed");
        _isFeeExempt[_addr] = _value;
        emit SetFeeExempted(_addr, _value);
    }

    function setTargetLiquidity(uint256 target, uint256 accuracy)
        external
        onlyOwner
    {
        targetLiquidity = target;
        targetLiquidityDenominator = accuracy;
        emit SetTargetLiquidity(target, accuracy);
    }

    function setSwapBackSettings(
        bool _enabled,
        uint256 _num,
        uint256 _denom
    ) external onlyOwner {
        swapEnabled = _enabled;
        gonSwapThreshold = TOTAL_GONS.div(_denom).mul(_num);
        emit SetSwapBackSettings(_enabled, _num, _denom);
    }

    function setFeeReceivers(
        address _liquidityReceiver,
        address _treasuryReceiver,
        address _riskFreeValueReceiver
    ) external onlyOwner {
        liquidityReceiver = _liquidityReceiver;
        treasuryReceiver = _treasuryReceiver;
        riskFreeValueReceiver = _riskFreeValueReceiver;
        emit SetFeeReceivers(_liquidityReceiver, _treasuryReceiver, _riskFreeValueReceiver);
    }

    function setFees(
        uint256 _liquidityFee,
        uint256 _riskFreeValue,
        uint256 _treasuryFee,
        uint256 _sellFeeTreasuryAdded,
        uint256 _feeDenominator
    ) external onlyOwner {
        require(
            _liquidityFee <= MAX_FEE_RATE &&
                _riskFreeValue <= MAX_FEE_RATE &&
                _treasuryFee <= MAX_FEE_RATE &&
                _sellFeeTreasuryAdded <= MAX_FEE_RATE,
            "wrong"
        );

        liquidityFee = _liquidityFee;
        buyFeeRFV = _riskFreeValue;
        treasuryFee = _treasuryFee;
        sellFeeTreasuryAdded = _sellFeeTreasuryAdded;
        totalBuyFee = liquidityFee.add(treasuryFee).add(buyFeeRFV);
        totalSellFee = totalBuyFee.add(sellFeeTreasuryAdded);

        require(totalBuyFee <= MAX_FEE_BUY, "Total BUY fee is too high");
        require(totalSellFee <= MAX_FEE_SELL, "Total SELL fee is too high");
        
        feeDenominator = _feeDenominator;
        require(totalBuyFee < feeDenominator / 4, "totalBuyFee");

        emit SetFees(_liquidityFee, _riskFreeValue, _treasuryFee, _sellFeeTreasuryAdded, _feeDenominator);
    }

    function clearStuckBalance(address _receiver) external onlyOwner {
        uint256 balance = address(this).balance;
        payable(_receiver).transfer(balance);
        emit ClearStuckBalance(_receiver);
    }

    function setAutoRebase(bool _autoRebase) external onlyOwner {
        require(autoRebase != _autoRebase, "Not changed");
        autoRebase = _autoRebase;
        emit SetAutoRebase(_autoRebase);
    }

    function setRebaseFrequency(uint256 _rebaseFrequency) external onlyOwner {
        require(_rebaseFrequency <= MAX_REBASE_FREQUENCY, "Too high");
        rebaseFrequency = _rebaseFrequency;
        emit SetRebaseFrequency(_rebaseFrequency);
    }

    function setRewardYield(
        uint256 _rewardYield,
        uint256 _rewardYieldDenominator
    ) external onlyOwner {
        rewardYield = _rewardYield;
        rewardYieldDenominator = _rewardYieldDenominator;
        emit SetRewardYield(_rewardYield,_rewardYieldDenominator);
    }

    function setIsLiquidityInETH(bool _value) external onlyOwner {
        require(isLiquidityInETH != _value, "Not changed");
        isLiquidityInETH = _value;
        emit SetIsLiquidityInETH(_value);
    }

    function setNextRebase(uint256 _nextRebase) external onlyOwner {
        nextRebase = _nextRebase;
        emit SetNextRebase(_nextRebase);
    }

    event SwapBack(
        uint256 contractTokenBalance,
        uint256 amountToLiquify,
        uint256 amountToRFV,
        uint256 amountToTreasury
    );
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ETHReceived,
        uint256 tokensIntoLiqudity
    );
    event SwapAndLiquifyUsdc(
        uint256 tokensSwapped,
        uint256 UsdcReceived,
        uint256 tokensIntoLiqudity
    );
    event LogRebase(uint256 indexed epoch, uint256 totalSupply);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event ManualRebase(int256 supplyDelta);
    event SetInitialDistributionFinished(bool _value);
    event SetFeeExempted(address _addr, bool _value);
    event SetTargetLiquidity(uint256 target, uint256 accuracy);
    event SetSwapBackSettings(bool _enabled, uint256 _num, uint256 _denom);
    event SetFeeReceivers(
        address _liquidityReceiver,
        address _treasuryReceiver,
        address _riskFreeValueReceiver
    );
    event SetFees(
        uint256 _liquidityFee,
        uint256 _riskFreeValue,
        uint256 _treasuryFee,
        uint256 _sellFeeTreasuryAdded,
        uint256 _feeDenominator
    );
    event ClearStuckBalance(address _receiver);
    event SetAutoRebase(bool _autoRebase);
    event SetRebaseFrequency(uint256 _rebaseFrequency);
    event SetRewardYield(uint256 _rewardYield, uint256 _rewardYieldDenominator);
    event SetIsLiquidityInETH(bool _value);
    event SetNextRebase(uint256 _nextRebase);

}
