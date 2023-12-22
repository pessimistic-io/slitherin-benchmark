// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./Ownable2Step.sol";
import "./Pausable.sol";
import "./Math.sol";
import "./IMainPool.sol";
import "./IMainPoolToken.sol";
import "./IRouter.sol";
import "./DexLibrary.sol";
import "./IWorkPool.sol";
import "./IOpenPnlFeed.sol";


contract MainPool is IMainPool, ERC20, Pausable, ReentrancyGuard, Ownable2Step {
    using Math for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    uint256 constant public DIVIDER = 10000;
    uint256 constant public PRECISION = 1e18;
    uint256 constant public MAX_FEE = 500;
    uint256[] WITHDRAW_EPOCHS_LOCKS;

    IWorkPool public workPool;
    IOpenPnlFeed public openTradesPnlFeed;

    address public stable;

    uint256 public collateralizationForRefill; // 95 (%)
    uint256 public collateralizationForDeplete; // 110 (%)
    uint256 public collateralizationForDepleteDelta;  // 10 (%)

    uint256 public exitFee;
    uint256 public joinFee;
    address public treasury;
    uint256 public maxRebalanceTvlReduce;
    uint256 public maxSwapTvlReduce;

    EnumerableSet.AddressSet internal _tokens;

    mapping(address => TokenConfiguration) public _tokenConfiguration;

    mapping(address => mapping(uint256 => uint256)) public withdrawRequests; // owner => unlock epoch => shares
    mapping(uint256 => address) public tokenPriorityId;

    event TokenPriorityIdConfigurationUpdated(TokenPriorityIdConfiguration[] configuration);
    event OpenTradesPnlFeedUpdated(address newAddress);
    event WorkPoolUpdated(address newAddress);

    event WithdrawRequested(address indexed owner, uint256 shares, uint256 currEpoch, uint256 indexed unlockEpoch);
    event WithdrawCanceled(address indexed owner, uint256 shares, uint256 currEpoch, uint256 indexed unlockEpoch);

    error MainPoolInvalidAddress(address account);
    error MainPoolInvalidToken(address token);
    error MainPoolInsufficientInputAmount();
    error MainPoolInvalidAmountUnderflow();
    error MainPoolRedeemMoreThanMax(uint256 amount);
    error MainPoolInsufficientUnderCollateralized();
    error MainPoolInsufficientOverCollateralized();
    error MainPoolInsufficientForRefill();
    error MainPoolInsufficientForDeplete();
    error MainPoolEndOfEpoch();
    error MainPoolInsufficientBalance();
    error mainPoolPendingWithdrawall();
    error MainPoolWrongParameters();
    error MainPoolInvalidWeight(uint256 amount);
    error MainPoolInvalidJoinFee(uint256 fee);
    error MainPoolInvalidExitFee(uint256 fee);
    error MainPoolInvalidMaxRebalanceTvlReduce(uint256 maxReduce);
    error MainPoolInvalidMaxSwapTvlReduce(uint256 maxReduce);
    error MainPoolExceedMaxRebalanceTvlReduce();
    error MainPoolExceedMaxSwapTvlReduce();


    constructor(
        address _owner,
        string memory _name,
        string memory _symbol,
        address _workPool,
        address _openTradesPnlFeed,

        FeeConfiguration memory feeConfiguration,
        PoolConfiguration memory poolConfiguration,
        TokenPriorityIdConfiguration[] memory tokenIdConfiguration
    ) ERC20(_name, _symbol) {

         _transferOwnership(_owner);
        _updateFeeConfiguration(feeConfiguration);
        _updatePoolConfiguration(poolConfiguration);
        _updateTokenPriorityIdConfiguration(tokenIdConfiguration);

        workPool = IWorkPool(_workPool);
        openTradesPnlFeed = IOpenPnlFeed(_openTradesPnlFeed);
        WITHDRAW_EPOCHS_LOCKS = [3, 2, 1];
    }

    function updateWorkPool(address newAddress) external onlyOwner returns (bool) {
        if (newAddress == address(0)) {
            revert MainPoolInvalidAddress(address(0));
        }
        workPool = IWorkPool(newAddress);
        emit WorkPoolUpdated(newAddress);
        return true;
    }

    function updateOpenTradesPnlFeed(address newAddress) external onlyOwner returns (bool) {
        if (newAddress == address(0)) {
            revert MainPoolInvalidAddress(address(0));
        }
        openTradesPnlFeed = IOpenPnlFeed(newAddress);
        emit OpenTradesPnlFeedUpdated(newAddress);
        return true;
    }

    function setCollateralizationLevels(
        uint256 _collateralizationForRefill, 
        uint256 _collateralizationForDeplete, 
        uint256 _collateralizationForDepleteDelta
    ) external onlyOwner returns (bool) {
        collateralizationForRefill = _collateralizationForRefill;
        collateralizationForDeplete = _collateralizationForDeplete;
        collateralizationForDepleteDelta = _collateralizationForDepleteDelta;
        return true;
    }

    function setMaxRebalanceTvlReduce(uint256 _maxRebalanceTvlReduce) external onlyOwner returns (bool) {
        if (maxRebalanceTvlReduce > PRECISION) revert MainPoolInvalidMaxRebalanceTvlReduce(_maxRebalanceTvlReduce);
        maxRebalanceTvlReduce = _maxRebalanceTvlReduce;
        return true;
    }

    function setMaxSwapTvlReduce(uint256 _maxSwapTvlReduce) external onlyOwner returns (bool) {
        if (maxSwapTvlReduce > PRECISION) revert MainPoolInvalidMaxSwapTvlReduce(_maxSwapTvlReduce);
        maxSwapTvlReduce = _maxSwapTvlReduce;
        return true;
    }

    function deposit(address tokenIn, uint256 amountIn, uint256 mintAmountOut) external whenNotPaused nonReentrant returns (uint256 mintAmount) {
        if (!tokensContains(tokenIn)) {
            revert MainPoolInvalidToken(tokenIn);
        }
        uint256 syntheticSupply = totalSupply();
      
        uint256 balanceFromWorkPoolShares = calculationStableFromWorkPoolShares();
        uint256 oldCalculationInStable = calculationStableForAllTokens() + balanceFromWorkPoolShares;
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 newCalculationInStable = calculationStableForAllTokens() + balanceFromWorkPoolShares;
        if (newCalculationInStable < oldCalculationInStable) {
            revert MainPoolInsufficientInputAmount();
        }
        mintAmount = syntheticSupply > 0
            ? (newCalculationInStable - oldCalculationInStable) * syntheticSupply / oldCalculationInStable
            : PRECISION;
        uint256 joinFeeAmount =  mintAmount * joinFee / DIVIDER;
        if (joinFeeAmount > 0) {
            _mint(treasury, joinFeeAmount);
            mintAmount -= joinFeeAmount;
        }
        if (mintAmount < mintAmountOut) {
            revert MainPoolInvalidAmountUnderflow();
        }        
        _mint(msg.sender, mintAmount);

        uint256 stableAmountToWorkPool;

         if (tokenIn != stable) {
            uint256 amountToWorkPool = amountIn / 2;

            IERC20(tokenIn).approve(address(_tokenConfiguration[tokenIn].tokenConnector), amountToWorkPool);
            stableAmountToWorkPool = _tokenConfiguration[tokenIn].tokenConnector.swapTokenToStable(amountToWorkPool, address(this));

        } else {
            stableAmountToWorkPool = amountIn / 2;
        }
        IERC20(stable).approve(address(workPool), stableAmountToWorkPool);
        workPool.deposit(stableAmountToWorkPool, address(this));

        emit Joined(msg.sender, tokenIn, amountIn, mintAmount, joinFeeAmount);
    }

    function withdraw(uint256 amountIn, uint256 minAmountOut) external nonReentrant returns (uint256 amountOut) {
        uint256 currentEpoch = workPool.currentEpoch();
        if (amountIn > maxRedeem(msg.sender)) {
            revert MainPoolRedeemMoreThanMax(amountIn);
        }
        withdrawRequests[msg.sender][currentEpoch] -= amountIn;

        uint256 syntheticSupply = totalSupply();
        uint256 exitFeeAmount = amountIn * exitFee / DIVIDER;
        _burn(msg.sender, amountIn);
        if (exitFeeAmount > 0) {
            _mint(treasury, exitFeeAmount);
            amountIn -= exitFeeAmount;
        }

        uint256 collateralizationLevel = workPool.collateralizationP();
        if (workPool.accPnlPerTokenUsed() < 0 && 
            workPool.accPnlPerToken() < 0 && 
            collateralizationLevel >= (collateralizationForDeplete + collateralizationForDepleteDelta) * PRECISION) deplete();

        uint256 amountStableToExitWithoutWorkPool = calculationStableForAllTokens() * amountIn / syntheticSupply;
        amountStableToExitWithoutWorkPool = collectRequiredAmountOfStable(amountStableToExitWithoutWorkPool);

        uint256 shareToRedeem = IERC20(address(workPool)).balanceOf(address(this)) * amountIn / syntheticSupply;
        uint256 amountStableToExitFromWorkPool = workPool.redeem(shareToRedeem, address(this), address(this));

        amountOut = amountStableToExitWithoutWorkPool + amountStableToExitFromWorkPool;

        if (amountOut < minAmountOut) {
            revert MainPoolInvalidAmountUnderflow();
        }        
        IERC20(stable).safeTransfer(msg.sender, amountOut);
        emit Exited(msg.sender, amountIn, amountOut, exitFeeAmount);
    }

    function refill() external whenNotPaused returns (uint256) {
        if (workPool.accPnlPerTokenUsed() <= 0) {
            revert MainPoolInsufficientUnderCollateralized();
        }
        uint256 collateralizationLevel = workPool.collateralizationP();
        if (collateralizationLevel > collateralizationForRefill * PRECISION) {
            revert MainPoolInsufficientForRefill();
        }

        uint256 stableAmount = uint256(workPool.accPnlPerTokenUsed()) * IERC20(address(workPool)).totalSupply() / PRECISION;
        collectRequiredAmountOfStable(stableAmount);

        IERC20(stable).approve(address(workPool), stableAmount);
        workPool.refill(stableAmount);
        return stableAmount;
    }

    function makeWithdrawRequest(uint256 shares) external returns (bool) {
        if (openTradesPnlFeed.nextEpochValuesRequestCount() != 0) {
            revert MainPoolEndOfEpoch();
        }
        uint256 currentEpoch = workPool.currentEpoch();

        if (totalSharesBeingWithdrawn(msg.sender) + shares > balanceOf(msg.sender)) {
            revert MainPoolInsufficientBalance();
        }
        uint unlockEpoch = currentEpoch + workPool.withdrawEpochsTimelock();
        withdrawRequests[msg.sender][unlockEpoch] += shares;

        emit WithdrawRequested(msg.sender, shares, currentEpoch, unlockEpoch);
        return true;
    }

    function cancelWithdrawRequest(uint256 shares, uint256 unlockEpoch) external returns (bool) {
        if (shares > withdrawRequests[msg.sender][unlockEpoch]) {
            revert MainPoolInsufficientBalance();
        }
        uint256 currentEpoch = workPool.currentEpoch();
        withdrawRequests[msg.sender][unlockEpoch] -= shares;

        emit WithdrawCanceled(msg.sender, shares, currentEpoch, unlockEpoch);
        return true;
    }

    function updateTokenPriorityIdConfiguration(TokenPriorityIdConfiguration[] memory tokenIdConfiguration) external onlyOwner returns (bool) {
        _updateTokenPriorityIdConfiguration(tokenIdConfiguration);
        return true;
    }

    function updatePoolConfiguration(PoolConfiguration memory poolConfiguration) external onlyOwner returns (bool) {
        if (totalSupply() > 0) {
            if (poolConfiguration.stable != stable) {
                revert MainPoolInvalidAddress(poolConfiguration.stable);
            }
        }
        _updatePoolConfiguration(poolConfiguration);
        rebalance();
        return true;
    }

    function updateFeeConfiguration(FeeConfiguration memory feeConfiguration) external onlyOwner returns (bool) {
        _updateFeeConfiguration(feeConfiguration);
        return true;
    }

    function pause() external onlyOwner returns (bool) {
        _pause();
        return true;
    }

    function unpause() external onlyOwner returns (bool) {
        _unpause();
        return true;
    }

    function tokensCount() external view returns (uint256) {
        return _tokens.length();
    }

    function tokens(uint256 index) external view returns (address) {
        return _tokens.at(index);
    }

    function weightsList(address[] memory tokens_) external view returns (uint256[] memory output) {
        uint256 tokensLength = tokens_.length;
        output = new uint256[](tokensLength);
        for (uint256 i; i < tokensLength;) {
            output[i] = _tokenConfiguration[tokens_[i]].weight;
            unchecked {
                ++i;
            }
        } 
    }

    function mainPoolOwner() external view returns (address) {
        return owner();
    }

    function deplete() public whenNotPaused returns (uint256) {
        if (workPool.accPnlPerTokenUsed() >= 0 || workPool.accPnlPerToken() >= 0) {
            revert MainPoolInsufficientOverCollateralized();
        }
        uint256 collateralizationLevel = workPool.collateralizationP();
        if (collateralizationLevel < (collateralizationForDeplete + collateralizationForDepleteDelta) * PRECISION) {
            revert MainPoolInsufficientForDeplete();
        }

        uint256 nominator = collateralizationLevel - collateralizationForDeplete * PRECISION;
        uint256 denominator = collateralizationLevel - 100 * PRECISION;

        uint256 stableAmount = uint256(workPool.accPnlPerTokenUsed() * (-1)) * nominator * IERC20(address(workPool)).totalSupply() / (denominator * PRECISION);
        workPool.deplete(stableAmount);

        return stableAmount;
    }

    function transfer(address to, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        if (totalSharesBeingWithdrawn(msg.sender) > balanceOf(msg.sender) - amount) {
            revert mainPoolPendingWithdrawall();
        }
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        if (totalSharesBeingWithdrawn(from) > balanceOf(from) - amount) {
            revert mainPoolPendingWithdrawall();
        }
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function rebalance() public onlyOwner returns (bool) {
        uint256 len = _tokens.length();
        bool[] memory checked = new bool[](len);
        uint256 currentTotalBalanceInStableAllTokens = calculationStableForAllTokens();
        for (uint256 i; i < len; i++) {
            address token_ = _tokens.at(i);
            TokenConfiguration memory tokenConfiguration_ = _tokenConfiguration[token_];
            if (token_ == stable) continue;
            uint256 targetBalanceTokenInStable = (currentTotalBalanceInStableAllTokens * tokenConfiguration_.weight) / DIVIDER;
            uint256 currentTokenBalanceInStable = calculationStableForToken(token_);
            if (targetBalanceTokenInStable < currentTokenBalanceInStable) {
                checked[i] = true;
                uint256 excessTokenInStable = currentTokenBalanceInStable - targetBalanceTokenInStable;
                uint256 amountTokenForSell = tokenConfiguration_.tokenConnector.getAmountOutStableToToken(excessTokenInStable);
                amountTokenForSell = tokenConfiguration_.tokenConnector.applyCoeffCorrectionToSell(amountTokenForSell);
                IERC20(token_).approve(address(tokenConfiguration_.tokenConnector), amountTokenForSell);
                tokenConfiguration_.tokenConnector.swapTokenToStable(amountTokenForSell, address(this));
            }
        }
        for (uint256 i; i < len; i++) {
            address token_ = _tokens.at(i);
            TokenConfiguration memory tokenConfiguration_ = _tokenConfiguration[token_];
            if (token_ == stable) continue;
            if (checked[i]) continue;
            uint256 targetBalanceTokenInStable = (currentTotalBalanceInStableAllTokens * tokenConfiguration_.weight) / DIVIDER;
            uint256 currentTokenBalanceInStable = calculationStableForToken(token_);
            if (targetBalanceTokenInStable > currentTokenBalanceInStable) {
                uint256 amountStableToSell = targetBalanceTokenInStable - currentTokenBalanceInStable;
                amountStableToSell = tokenConfiguration_.tokenConnector.applyCoeffCorrectionToSell(amountStableToSell);
                IERC20(stable).approve(address(tokenConfiguration_.tokenConnector), amountStableToSell);
                tokenConfiguration_.tokenConnector.swapStableToToken(amountStableToSell, address(this));
            }
        }
        uint256 afterRebalanceTotalBalanceInStableAllTokens = calculationStableForAllTokens();
        if (afterRebalanceTotalBalanceInStableAllTokens < currentTotalBalanceInStableAllTokens &&
            ((currentTotalBalanceInStableAllTokens - afterRebalanceTotalBalanceInStableAllTokens) * PRECISION / 
                currentTotalBalanceInStableAllTokens > maxRebalanceTvlReduce)) revert MainPoolExceedMaxRebalanceTvlReduce();
        return true;
    }

    function calculationStableForAllTokens() public returns (uint256 amount) {
        uint256 len = _tokens.length();
        for (uint256 i; i < len;) {
            amount += calculationStableForToken(_tokens.at(i));
            unchecked {
                ++i;
            }
        }
    }

    function calculationStableForToken(address token_) public returns (uint256 amount) {
        IERC20 token = IERC20(token_);
        if (token_ == stable) amount = token.balanceOf(address(this));
        else {
            uint256 currentBalanceTokenInPool = token.balanceOf(address(this));
            amount = _tokenConfiguration[token_].tokenConnector.getAmountOutTokenToStable(currentBalanceTokenInPool);
        }
    }

    function maxRedeem(address owner) public view returns (uint256) {
        uint256 currentEpoch = workPool.currentEpoch();
        return
            openTradesPnlFeed.nextEpochValuesRequestCount() == 0
                ? Math.min(withdrawRequests[owner][currentEpoch], totalSupply())
                : 0;
    }

    function tokensContains(address token) public view returns (bool) {
        return _tokens.contains(token);
    }

    function collectRequiredAmountOfStable(uint256 _amount) private returns (uint256) {
        if (_amount > calculationStableForAllTokens()) {
            revert MainPoolInsufficientBalance();
        }

        uint256 totalBalanceInStableAllTokensBeforeOperation = calculationStableForAllTokens();
        uint256 remainAmount = _amount;

        uint256 _tokensLength = _tokens.length();
        for (uint256 i = 1; i <= _tokensLength;) {
            if (remainAmount == 0) break;
            address token_ = tokenPriorityId[i];
            uint256 balanceToken = IERC20(token_).balanceOf(address(this));

            if (token_ == stable) {
                remainAmount = remainAmount > balanceToken ? remainAmount : 0;
            } else {

                IERC20(token_).approve(address(_tokenConfiguration[token_].tokenConnector), balanceToken);
                _tokenConfiguration[token_].tokenConnector.swapTokenToStable(balanceToken, address(this));
                uint256 stableBalance = IERC20(stable).balanceOf(address(this));

                if (stableBalance > remainAmount) {
                    uint256 amountSwapBackToToken = stableBalance - remainAmount;

                    IERC20(stable).approve(address(_tokenConfiguration[stable].tokenConnector), amountSwapBackToToken);
                    _tokenConfiguration[token_].tokenConnector.swapStableToToken(amountSwapBackToToken, address(this));

                    remainAmount = 0;
                }
            }
            unchecked {
                ++i;
            }
        }

        uint256 totalBalanceInStableAllTokensAfterOperation = calculationStableForAllTokens();
        if (totalBalanceInStableAllTokensAfterOperation < totalBalanceInStableAllTokensBeforeOperation &&
            ((totalBalanceInStableAllTokensBeforeOperation - totalBalanceInStableAllTokensAfterOperation) * PRECISION / 
                totalBalanceInStableAllTokensBeforeOperation > maxSwapTvlReduce)) revert MainPoolExceedMaxSwapTvlReduce();

        return remainAmount == 0 ? _amount : IERC20(stable).balanceOf(address(this));
    }

    function _updateTokenPriorityIdConfiguration(TokenPriorityIdConfiguration[] memory configuration_) private {
        if (configuration_.length != _tokens.length()) {
            revert MainPoolWrongParameters();
        }

        uint256 _tokensLength = _tokens.length();
        for (uint256 i; i < _tokensLength;) {
            TokenPriorityIdConfiguration memory config = configuration_[i];

            if (!tokensContains(config.token)) {
                revert MainPoolInvalidToken(config.token);
            }

            if (config.id == 1) {
                if (config.token != stable) {
                    revert MainPoolWrongParameters();
                }
            } 
            tokenPriorityId[config.id] = config.token;
            unchecked {
                ++i;
            }
        }
        emit TokenPriorityIdConfigurationUpdated(configuration_);
    }

    function _updatePoolConfiguration(PoolConfiguration memory configuration_) private {
        if (stable == address(0)) {
            if (configuration_.stable == address(0)) {
                revert MainPoolInvalidAddress(address(0));
            }
            stable = configuration_.stable;
        }

        uint256 totalBalanceInStableAllTokensBeforeOperation = calculationStableForAllTokens();

        bool[] memory isTokenInNewSet = new bool[](_tokens.length());
        uint256 weightSum = 0;
        uint256 configurationsLength = configuration_.tokenConfigurations.length;
        uint256 _tokensLength = _tokens.length();
        for (uint256 i; i < _tokensLength;) {
            address currentToken = _tokens.at(i);
            uint256 currentBalance = IERC20(currentToken).balanceOf(address(this));
            for (uint256 j; j < configurationsLength; j++) {
                if (currentToken == configuration_.tokenConfigurations[j].token) {
                    isTokenInNewSet[i] = true;
                    break;
                }
            }
            if (!isTokenInNewSet[i]) {
                TokenConfiguration memory tokenConfiguration_ = _tokenConfiguration[currentToken];
                IERC20(currentToken).approve(address(tokenConfiguration_.tokenConnector), currentBalance);
                tokenConfiguration_.tokenConnector.swapTokenToStable(currentBalance, address(this));
            }
            unchecked {
                ++i;
            }
        }
        if (isTokenInNewSet.length > 0) {
            uint256 len = isTokenInNewSet.length;
            for (uint256 i = len - 1; i >= 0; i--) {
                if (!isTokenInNewSet[i]) _tokens.remove(_tokens.at(i));
                if (i == 0) break;
            }
        }
        for (uint256 i; i < configurationsLength;) {
            TokenConfiguration memory newTokenConfiguration = configuration_.tokenConfigurations[i];
            if (address(newTokenConfiguration.tokenConnector) == address(0)) {
                revert MainPoolInvalidAddress(address(0));
            }
            if (address(newTokenConfiguration.tokenConnector.stable()) != configuration_.stable) {
                revert MainPoolInvalidAddress(address(newTokenConfiguration.tokenConnector.stable()));
            }
            _tokens.add(newTokenConfiguration.token);
            if (newTokenConfiguration.weight == 0) {
                revert MainPoolInvalidWeight(0);
            }

            TokenConfiguration storage tokenConfiguration = _tokenConfiguration[newTokenConfiguration.token];
            tokenConfiguration.token = newTokenConfiguration.token;
            tokenConfiguration.weight = newTokenConfiguration.weight;
            tokenConfiguration.tokenConnector = newTokenConfiguration.tokenConnector;

            weightSum += tokenConfiguration.weight;
            unchecked {
                ++i;
            }
        }
        if (!_tokens.contains(stable) || weightSum != DIVIDER || _tokens.length() != configurationsLength) {
            revert MainPoolWrongParameters();
        }

        uint256 totalBalanceInStableAllTokensAfterOperation = calculationStableForAllTokens();
        if (totalBalanceInStableAllTokensAfterOperation < totalBalanceInStableAllTokensBeforeOperation &&
            ((totalBalanceInStableAllTokensBeforeOperation - totalBalanceInStableAllTokensAfterOperation) * PRECISION / 
                totalBalanceInStableAllTokensBeforeOperation > maxSwapTvlReduce)) revert MainPoolExceedMaxSwapTvlReduce();

        emit PoolConfigurationUpdated(configuration_);
    }

    function _updateFeeConfiguration(FeeConfiguration memory configuration_) private {
        if (configuration_.treasury == address(0)) {
            revert MainPoolInvalidAddress(address(0));
        }
        if (configuration_.joinFee > MAX_FEE) {
            revert MainPoolInvalidJoinFee(configuration_.joinFee);
        }
        if (configuration_.exitFee > MAX_FEE) {
            revert MainPoolInvalidExitFee(configuration_.exitFee);
        }
        treasury = configuration_.treasury;
        joinFee = configuration_.joinFee;
        exitFee = configuration_.exitFee;
        emit FeeConfigurationUpdated(configuration_);
    }

    function totalSharesBeingWithdrawn(address owner) private view returns (uint256 shares) {
        uint256 currentEpoch = workPool.currentEpoch();
        for (uint256 i = currentEpoch; i <= currentEpoch + WITHDRAW_EPOCHS_LOCKS[0];) {
            shares += withdrawRequests[owner][i];
            unchecked {
                ++i;
            }
        }
    }

    function calculationStableFromWorkPoolShares() private view returns (uint256) {
        uint256 sharesBalance = IERC20(address(workPool)).balanceOf(address(this));
        uint256 shareToStablePrice = workPool.shareToAssetsPrice();
        return sharesBalance.mulDiv(shareToStablePrice, PRECISION, Math.Rounding.Down);
    }
}

