// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { AccessControlUpgradeable } from "./AccessControlUpgradeable.sol";
import { Initializable } from "./Initializable.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeCast } from "./SafeCast.sol";
import { SafeMath } from "./SafeMath.sol";
import { SignedSafeMath } from "./SignedSafeMath.sol";
import { DoubleEndedQueue } from "./DoubleEndedQueue.sol";
import { IUniswapV2Factory } from "./IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "./IUniswapV2Pair.sol";
import { IUniswapV2Router02 } from "./IUniswapV2Router02.sol";

contract FarmerDoge is Initializable, ERC20Upgradeable, PausableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeMath for uint;
    using SignedSafeMath for int256;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint88 private constant MAGNITUDE = 2 ** 84;
    uint88 public maxWalletAmount;
    uint88 public maxTxAmount;
    uint88 public minimumTokensBeforeSwap;
    uint96 public dividendShares;
    uint8 public numClaimsToProcess;
    uint public totalDividendsDistributed;
    IERC20 public rewardToken;

    uint8 public feeOnBuy;
    uint8 public feeOnSell;
    uint8 private marketingRatio;

    uint64 private minimumTokenBalanceForDividends;
    bool private _swapping;
    uint private magnifiedDividendPerShare;

    IUniswapV2Router02 public router;
    IUniswapV2Pair public pair;

    address public treasuryWallet;
    address[] private tokenToNativePath;
    address[] private nativeToRewardPath;

    mapping(address => bool) private _isAllowedToTradeWhenDisabled;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcludedFromMaxTransactionLimit;
    mapping(address => bool) private _isExcludedFromMaxWalletLimit;
    mapping(address => bool) private _automatedMarketMakerPairs;
    mapping(address => bool) private _excludedFromDividends;
    mapping(address => int256) private _magnifiedDividendCorrections;
    mapping(address => uint) private _withdrawnDividends;

    DoubleEndedQueue.Bytes32Deque public payoutQueue;

    event DividendsDistributed(
        address indexed from,
        uint weiAmount
    );
    event DividendWithdrawn(
        address indexed to,
        uint weiAmount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address routerAddress, address initialReward) public initializer{
        __ERC20_init("FarmerDoge", "CROP");
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        uint256 initialSupply = 1000000000 * 10 ** decimals();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _mint(msg.sender, initialSupply);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _pause();

        IUniswapV2Router02 _router = IUniswapV2Router02(routerAddress);
        pair = IUniswapV2Pair(IUniswapV2Factory(_router.factory()).createPair(address(this), _router.WETH()));
        router = _router;
        _approve(address(this), routerAddress, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

        feeOnBuy = 10;
        feeOnSell = 10;

        numClaimsToProcess = 4;

        marketingRatio = 20;

        tokenToNativePath = new address[](2);
        tokenToNativePath[0] = address(this);
        tokenToNativePath[1] = router.WETH();

        nativeToRewardPath = new address[](2);
        nativeToRewardPath[0] = router.WETH();
        nativeToRewardPath[1] = initialReward;
        rewardToken = IERC20(initialReward);

        treasuryWallet = msg.sender;
        minimumTokensBeforeSwap = SafeCast.toUint80(SafeMath.div(totalSupply(), 10000));
        maxWalletAmount = SafeCast.toUint88(initialSupply.div(50));
        maxTxAmount = SafeCast.toUint88(initialSupply.div(100));

        dividendShares = SafeCast.toUint96(totalSupply());

        excludeFromDividends(address(this), true);
        excludeFromDividends(address(0x000000000000000000000000000000000000dEaD), true);
        excludeFromDividends(address(0), true);

        _isExcludedFromFee[msg.sender] = true;
        _isExcludedFromFee[address(this)] = true;

        _isAllowedToTradeWhenDisabled[msg.sender] = true;

        _isExcludedFromMaxTransactionLimit[address(this)] = true;

        _isExcludedFromMaxWalletLimit[address(pair)] = true;
        _isExcludedFromMaxWalletLimit[address(router)] = true;
        _isExcludedFromMaxWalletLimit[address(this)] = true;
        _isExcludedFromMaxWalletLimit[msg.sender] = true;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal onlyRole(UPGRADER_ROLE) override {}
    
    function setAutomatedMarketMakerPair(address mmPair, bool value) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _automatedMarketMakerPairs[mmPair] = value;
        excludeFromDividends(mmPair, value);
    }

    function allowTradingWhenDisabled(address account, bool allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _isAllowedToTradeWhenDisabled[account] = allowed;
    }

    function excludeFromFees(address account, bool excluded) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _isExcludedFromFee[account] = excluded;
    }

    function excludeFromMaxTransactionLimit(address account, bool excluded) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _isExcludedFromMaxTransactionLimit[account] = excluded;
    }

    function excludeFromMaxWalletLimit(address account, bool excluded) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _isExcludedFromMaxWalletLimit[account] = excluded;
    }

    function setTreasuryWallet(address newTreasureyWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        treasuryWallet = newTreasureyWallet;
    }

    function setBuyFee(uint8 newFee) public onlyRole(DEFAULT_ADMIN_ROLE) {
        feeOnBuy = newFee;
    }

    function setSellFee(uint8 newFee) public onlyRole(DEFAULT_ADMIN_ROLE) {
        feeOnSell = newFee;
    }

    function setMaxTransactionAmount(uint88 newMaxTxAmount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        maxTxAmount = newMaxTxAmount;
    }

    function setMaxWalletAmount(uint88 newMaxWalletAmount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        maxWalletAmount = newMaxWalletAmount;
    }

    function setMinimumTokensBeforeSwap(uint88 newMinTokensBeforeSwap) public onlyRole(DEFAULT_ADMIN_ROLE) {
        minimumTokensBeforeSwap = newMinTokensBeforeSwap;
    }

    function setMarketingRatio(uint8 newMarketingRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
        marketingRatio = newMarketingRatio;
    }
    
    function excludeFromDividends(address account, bool value) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _excludedFromDividends[account] = value;
        if(balanceOf(account) > 0 ){
            if (value) {
                _burnShares(account, balanceOf(account));
            } else {
                _mintShares(account, balanceOf(account));
            }
        }
    }

    function setTokenBalanceForDividends(uint32 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minimumTokenBalanceForDividends = newValue;
    }

    function setRewardToken(address token) public onlyRole(DEFAULT_ADMIN_ROLE) {
        nativeToRewardPath[0] = router.WETH();
        nativeToRewardPath[1] = address(token);
        rewardToken = IERC20(token);
    }

    function setNumClaimsToProcess(uint8 claims) public onlyRole(DEFAULT_ADMIN_ROLE) {
        numClaimsToProcess = claims;
    }

    function _transfer(address from, address to, uint amount) override internal {
        bool isBuyFromLp = _automatedMarketMakerPairs[from];
        bool isSelltoLp = _automatedMarketMakerPairs[to];

        if (!_isAllowedToTradeWhenDisabled[from] && !_isAllowedToTradeWhenDisabled[to]) {
            require(!paused(), "Trading disabled");
            if (!_isExcludedFromMaxTransactionLimit[to] && !_isExcludedFromMaxTransactionLimit[from]) {
                require(amount <= maxTxAmount, "Exceeds max");
            }
            if (!_isExcludedFromMaxWalletLimit[to]) {
                require(balanceOf(to).add(amount) <= maxWalletAmount, "Exceeds max");
            }
        }
        uint8 tax = _adjustTaxes(isBuyFromLp, isSelltoLp);
        if (
            !paused() &&
            balanceOf(address(this)) >= minimumTokensBeforeSwap &&
            !_swapping &&
            tax > 0 &&
            isSelltoLp
        ) {
            _swapping = true;
            _swapAndDistribute();
            _swapping = false;
        }
        if (!_swapping && !paused() && !_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
            uint256 fee = amount.mul(tax).div(100);
            amount = amount.sub(fee);
            if (fee > 0) {
                super._transfer(from, address(this), fee);
            }
        }
        super._transfer(from, to, amount);
        bytes32 add = bytes32(uint256(uint160(to)));
        if(!_excludedFromDividends[to]) DoubleEndedQueue.pushBack(payoutQueue, add);

        if(_excludedFromDividends[from] && !_excludedFromDividends[to]) _mintShares(from, amount);
        if(!_excludedFromDividends[from] && _excludedFromDividends[to]) _burnShares(to, amount);

        int256 _magCorrection = SafeCast.toInt256(magnifiedDividendPerShare.mul(amount));
        _magnifiedDividendCorrections[from] = _magnifiedDividendCorrections[from].add(_magCorrection);
        _magnifiedDividendCorrections[to] = _magnifiedDividendCorrections[to].sub(_magCorrection);
    }

    // Dividend Logic
    receive() external payable {
        distributeDividends(msg.value);
    }

    function distributeDividends(uint256 amount) public payable {
        if (amount > 0) {
            magnifiedDividendPerShare = magnifiedDividendPerShare.add((amount).mul(MAGNITUDE) / dividendShares);
            emit DividendsDistributed(msg.sender, amount);
        }
    }

    function claimNativeOverflow(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amount == 0){
            amount = address(this).balance;
        }
        (bool success,) = address(msg.sender).call{value : amount}("");
        if (success) {
            magnifiedDividendPerShare = magnifiedDividendPerShare.sub((amount).mul(MAGNITUDE) / dividendShares);
        }
    }
    
    function _adjustTaxes(bool isBuyFromLp, bool isSellToLp) private view returns (uint8 _fee) {
        if (!isBuyFromLp && !isSellToLp) {
            _fee = 0;
        } else if (isSellToLp && isBuyFromLp) {
            _fee = 15;
        }else if (isSellToLp) {
            _fee = feeOnSell;
        } else {
            _fee = feeOnBuy;
        }
    }

    function _swapAndDistribute() internal returns (bool distributed){
        uint256 initialNativeBalance = address(this).balance;
        uint256 tokenBalance = balanceOf(address(this));

        swapTokensForNative(tokenBalance);

        uint256 nativeBalanceAfterSwap = address(this).balance.sub(initialNativeBalance);

        uint256 amountNativeMarketing = nativeBalanceAfterSwap.mul(marketingRatio).div(100);
        uint256 amountNativeDividends = nativeBalanceAfterSwap.sub(amountNativeMarketing);
        (bool _distributed,) = payable(treasuryWallet).call{value : amountNativeMarketing, gas : 30000}("");

        distributeDividends(amountNativeDividends);
        return _distributed;
    }

    function swapTokensForNative(uint256 tokenAmount) internal {
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            1,
            tokenToNativePath,
            address(this),
            // solhint-disable-next-line not-rely-on-time
            block.timestamp
        );
    }

    function withdrawDividend(address account) internal returns (uint withdrawn) {
        uint _withdrawableDividend = withdrawableDividendOf(account);
        if (_withdrawableDividend > 0) {
            _withdrawnDividends[account] = _withdrawnDividends[account].add(_withdrawableDividend);
            emit DividendWithdrawn(account, _withdrawableDividend);
            bool success = swapNativeForRewards(account, _withdrawableDividend);
            if(!success) _withdrawnDividends[account] = _withdrawnDividends[account].sub(_withdrawableDividend);
        }
        return _withdrawableDividend;
    }

    function dividendOf(address account) public view returns(uint) {
        return withdrawableDividendOf(account);
    }

    function withdrawableDividendOf(address account) public view returns(uint) {
        return accumulativeDividendOf(account).sub(_withdrawnDividends[account]);
    }

    function withdrawnDividendOf(address account) public view returns(uint) {
        return _withdrawnDividends[account];
    }

    function accumulativeDividendOf(address account) public view returns(uint) {
        return SafeCast.toUint256(SafeCast.toInt256(magnifiedDividendPerShare.mul(balanceOf(account)))
            .add(_magnifiedDividendCorrections[account])) / MAGNITUDE;
    }

    function _mintShares(address account, uint amount) internal {
        dividendShares += SafeCast.toUint96(amount);
        _magnifiedDividendCorrections[account] = _magnifiedDividendCorrections[account]
            .sub(SafeCast.toInt256(magnifiedDividendPerShare.mul(amount)));
    }

    function _burnShares(address account, uint amount) internal {
        dividendShares -= SafeCast.toUint96(amount);

        _magnifiedDividendCorrections[account] = _magnifiedDividendCorrections[account]
         .add(SafeCast.toInt256(magnifiedDividendPerShare.mul(amount)));
    }

    function getNumberOfTokenHolders() external view returns (uint holders) {
        return DoubleEndedQueue.length(payoutQueue);
    }

    function rescueToken(address tokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool success) {
        return IERC20(tokenAddress).transfer(msg.sender, IERC20(tokenAddress).balanceOf(address(this)));
    }

    function getAccount(address _account)
    public view returns (
        address account,
        uint withdrawableDividends,
        uint totalDividends) {
        account = _account;
        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);
    }

    function claimReward() external returns (uint256 reward) {
        return processAccount(payable(msg.sender));
    }

    function processAccount(address payable account) public  returns (uint256 reward) {
        return withdrawDividend(account);
    }

    function process(uint accounts) public onlyRole(DEFAULT_ADMIN_ROLE) returns (uint numProcessed, uint numClaims) {
        uint iterations = 0;
        uint claims = 0;
        address[] memory addresses = new address[](accounts);
        uint[] memory amounts = new uint[](accounts);
        uint totalDivs = 0;

        while(claims < accounts) {
            address account = address(uint160(uint(DoubleEndedQueue.popFront(payoutQueue))));
            if(balanceOf(account) > 0 && !_excludedFromDividends[account]) {
                addresses[claims] = account;
                amounts[claims] = withdrawableDividendOf(account);
                totalDivs += amounts[claims];
                claims++;
            }
            iterations++;
        }
        uint bought = swapNativeForRewards(totalDivs);
        if (bought > 0) {
            for(uint i = 0; i < addresses.length; i++) {
                uint rewardPercent = amounts[i].mul(MAGNITUDE).div(totalDivs);
                uint amountInNative = rewardPercent.mul(totalDivs).div(MAGNITUDE);
                uint rewardAmount = rewardPercent.mul(bought).div(MAGNITUDE);
                _withdrawnDividends[addresses[i]] = _withdrawnDividends[addresses[i]].add(amountInNative);
                bool success = rewardToken.transfer(addresses[i], rewardAmount);
                // solhint-disable-next-line reentrancy
                if (!success) _withdrawnDividends[addresses[i]] = _withdrawnDividends[addresses[i]].sub(amountInNative);
                DoubleEndedQueue.pushBack(payoutQueue, bytes32(uint256(uint160(addresses[i]))));
            }
        }
        return (iterations, claims);
    }

    function swapNativeForRewards(uint amount) private returns (uint) {
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value : amount}(
            1,
            nativeToRewardPath,
            address(this),
            // solhint-disable-next-line not-rely-on-time
            block.timestamp
        );
        return amount;
    }

    function swapNativeForRewards(address account, uint amount) private returns (bool) {
        try router.swapExactETHForTokensSupportingFeeOnTransferTokens{value : amount}(
                1,
                nativeToRewardPath,
                address(account),
                // solhint-disable-next-line not-rely-on-time
                block.timestamp
            ) {
            return true;
        } catch {
            return false;
        }
    }
}

