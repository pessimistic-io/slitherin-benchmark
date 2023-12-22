// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Initializable.sol";

import "./SafeERC20.sol";
import "./IERC20.sol";

import "./IHedgedThetaVault.sol";
import "./IHedgedThetaVaultManagement.sol";
import "./IPlatform.sol";
import "./IMegaThetaVault.sol";
import "./IComputedCVIOracle.sol";

contract HedgedThetaVault is Initializable, IHedgedThetaVault, IHedgedThetaVaultManagement, OwnableUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    uint32 internal constant MAX_PERCENTAGE = 1000000;

    address public fulfiller;
    address public hedgeAdjuster;

    IERC20 internal token;
    IPlatform internal inversePlatform;
    IMegaThetaVault internal megaThetaVault;
    IRewardRouter public rewardRouter;
    address public thetaRewardTracker;

    uint256 public initialTokenToHedgedThetaTokenRate;
    uint32 public depositHoldingsPercentage;
    uint32 public withdrawFeePercentage;

    uint32 public minCVIDiffAllowedPercentage; // Obsolete

    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _initialTokenToHedgedThetaTokenRate, IPlatform _inversePlatform, IMegaThetaVault _megaThetaVault, 
            IERC20 _token, string memory _lpTokenName, string memory _lpTokenSymbolName) public initializer {

        require(address(_inversePlatform) != address(0));
        require(address(_megaThetaVault) != address(0));
        require(address(_token) != address(0));
        require(_initialTokenToHedgedThetaTokenRate > 0);

        initialTokenToHedgedThetaTokenRate = _initialTokenToHedgedThetaTokenRate;
        depositHoldingsPercentage = 250000;
        withdrawFeePercentage = 1000;

        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        OwnableUpgradeable.__Ownable_init();
        ERC20Upgradeable.__ERC20_init(_lpTokenName, _lpTokenSymbolName);

        token = _token;
        inversePlatform = _inversePlatform;
        megaThetaVault = _megaThetaVault;

        token.safeApprove(address(megaThetaVault), type(uint256).max);
        IERC20(address(megaThetaVault)).safeApprove(address(megaThetaVault), type(uint256).max);
        token.safeApprove(address(inversePlatform), type(uint256).max);
    }

    function depositForOwner(address _owner, uint168 _tokenAmount, uint32 _realTimeCVIValue, bool _shouldStake) external override returns (uint256 hedgedThetaTokensMinted) {
        require(msg.sender == fulfiller);
        require(_tokenAmount > 0, "Zero amount");

        uint168 holdings = _tokenAmount * depositHoldingsPercentage / MAX_PERCENTAGE;

        uint256 supply = totalSupply();

        (uint32 cviValue,,) = megaThetaVault.thetaVault().volToken().platform().cviOracle().getCVILatestRoundData();

        uint32 megaThetaVaultBalanceCVI = cviValue;
        if (_realTimeCVIValue < megaThetaVaultBalanceCVI) {
            megaThetaVaultBalanceCVI = _realTimeCVIValue;
        }

        uint32 reversePlatformBalanceCVI = cviValue;
        if (_realTimeCVIValue > reversePlatformBalanceCVI) {
            reversePlatformBalanceCVI = _realTimeCVIValue;
        }

        // Using min cvi for the mega theta vault balance (as it makes the platform balance larger), and max cvi for the inverse balance (that makes the inverse platform balance larger),
        // so that the total balance will be higher, and user's share smaller, not allowing front run
        (uint256 balance,,,) = totalBalance(megaThetaVaultBalanceCVI, reversePlatformBalanceCVI);
    
        if (supply > 0 && balance > 0) {
            hedgedThetaTokensMinted = _tokenAmount * supply / balance;
        } else {
            hedgedThetaTokensMinted = _tokenAmount * initialTokenToHedgedThetaTokenRate;
        }

        _mint(_shouldStake ? address(this) : _owner, hedgedThetaTokensMinted);

        token.safeTransferFrom(_owner, address(this), _tokenAmount);
        megaThetaVault.deposit(_tokenAmount - holdings, cviValue);

        if (_shouldStake) {
            rewardRouter.stakeForAccount(StakedTokenName.HEDGED_VAULT, _owner, hedgedThetaTokensMinted);
        }

        emit HedgedDeposit(_owner, _tokenAmount, holdings, hedgedThetaTokensMinted);
    }

    function withdrawForOwner(address _owner, uint168 _hedgedThetaTokenAmount, uint32 _realTimeCVIValue) external override returns (uint256 tokensReceived) {
        require(_hedgedThetaTokenAmount > 0, "Zero amount");
        
        uint256 totalHoldings = token.balanceOf(address(this));
        uint256 holdingsToWithdraw = totalHoldings * _hedgedThetaTokenAmount / totalSupply();
        uint256 lpTokensToWithdraw = IERC20(address(inversePlatform)).balanceOf(address(this)) * _hedgedThetaTokenAmount / totalSupply();
        uint168 thetaTokensToWithdraw = uint168(IERC20(address(megaThetaVault)).balanceOf(address(this)) * _hedgedThetaTokenAmount / totalSupply());

        (uint32 cviValue,,) = megaThetaVault.thetaVault().volToken().platform().cviOracle().getCVILatestRoundData();

        if (lpTokensToWithdraw > 0) {
            uint32 inversePlatformBalanceCVI = cviValue;
            if (_realTimeCVIValue < inversePlatformBalanceCVI) {
                inversePlatformBalanceCVI = _realTimeCVIValue;
            }

            // We use maximum cvi for the inverse platform balance, so that the balance is minimal (positions are short and worth more),
            // thus not allowing front run
            (uint256 inversePlatformBalance,) = inversePlatform.totalBalance(true, inversePlatformBalanceCVI);
            uint256 amountExpectedToWithdraw = lpTokensToWithdraw * 
                inversePlatformBalance / IERC20(address(inversePlatform)).totalSupply();

            // Check if withdrawing is possible, and if not, try to compensate from holdings, otherwise revert
            (bool canWithdrawEnough, uint256 maxLPTokensWithdrawPossible) = inversePlatform.canWithdraw(amountExpectedToWithdraw, inversePlatformBalanceCVI);
            if (!canWithdrawEnough) {
                lpTokensToWithdraw = maxLPTokensWithdrawPossible;
            }

            // Need to withdraw so that outcome is smallest, so inverse cvi should be lowest, so cvi should be max
            (, tokensReceived) = inversePlatform.withdrawLPTokens(lpTokensToWithdraw, inversePlatformBalanceCVI);

            if (!canWithdrawEnough) {
                holdingsToWithdraw += (amountExpectedToWithdraw - tokensReceived);
                require(holdingsToWithdraw < totalHoldings, "Not enough holdings");
            }
        }

        tokensReceived += holdingsToWithdraw;

        {
            uint32 burnCVIValue = cviValue;
            uint32 withdrawCVIValue = cviValue;

            if (_realTimeCVIValue > withdrawCVIValue) {
                withdrawCVIValue = _realTimeCVIValue;
            }

            if (_realTimeCVIValue < burnCVIValue) {
                burnCVIValue = _realTimeCVIValue;
            }

            // Need to minimize amounts when withdrawing, so for burning, 
            // cvi should be minimum, and for withdrawing from platform, it should be maximum (making the total balance smaller),
            // so to not allow front run
            tokensReceived += megaThetaVault.withdraw(thetaTokensToWithdraw, burnCVIValue, withdrawCVIValue);
        }

        _burn(_owner, _hedgedThetaTokenAmount);

        uint256 withdrawFee = tokensReceived * withdrawFeePercentage / MAX_PERCENTAGE;
        tokensReceived -= withdrawFee;

        // Note: approving just before sending to support updating the feesCollector via setter in Platform
        IFeesCollector feesCollector = megaThetaVault.thetaVault().platform().feesCollector();
        token.safeApprove(address(feesCollector), withdrawFee);
        feesCollector.sendProfit(withdrawFee, IERC20(address(token)));
        token.safeTransfer(_owner, tokensReceived);

        emit HedgedWithdraw(_owner, tokensReceived, _hedgedThetaTokenAmount);
    }

    function adjustHedge(bool _withdrawFromVault) external override {
        require(msg.sender == hedgeAdjuster, 'Not Allowed');
        (uint32 cviValue,,) = megaThetaVault.thetaVault().volToken().platform().cviOracle().getCVILatestRoundData();

        uint256 totalOIBalance = megaThetaVault.calculateOIBalance();
        uint256 targetExtraLiquidityNeeded = totalOIBalance * 
            (uint256(cviValue) - inversePlatform.minCVIValue()) * inversePlatform.maxPositionProfitPercentageCovered() / MAX_PERCENTAGE / cviValue;

        uint256 currentExtraLiquidity = inversePlatform.totalLeveragedTokensAmount() - inversePlatform.totalPositionsOriginalAmount();

        if (targetExtraLiquidityNeeded > currentExtraLiquidity) {
            uint256 amountToDeposit = targetExtraLiquidityNeeded - currentExtraLiquidity;
            uint256 totalHoldings = token.balanceOf(address(this));
            if (amountToDeposit > totalHoldings) {
                if (_withdrawFromVault) {
                    // Note: in this case, the holdings are not enough, so attempt to withdraw from mega theta vault to
                    // compenstate. If such withdraw reverts, the adjustHedge will revert, waiting for its next run hoping that
                    // withdraw will be possible. The theta vault's cap should increase greatly the chances of the withdraw
                    // succeeding unless in rare edge cases
                    uint256 amountToWithdraw = amountToDeposit - totalHoldings;
                    (uint256 megaThetaBalance,,) = megaThetaVault.totalBalance(cviValue);
                    uint256 thetaTokensToWithdraw = amountToWithdraw * 
                        IERC20(address(megaThetaVault)).balanceOf(address(this)) / megaThetaBalance;
                    require(uint168(thetaTokensToWithdraw) == thetaTokensToWithdraw);
                    uint256 withdrawTokens = megaThetaVault.withdraw(uint168(thetaTokensToWithdraw), cviValue, cviValue);

                    amountToDeposit = totalHoldings + withdrawTokens;
                } else {
                    amountToDeposit = totalHoldings;   
                }
            }

            inversePlatform.deposit(amountToDeposit, 0, cviValue);
        } else {
            uint256 amountToWithdraw = currentExtraLiquidity - targetExtraLiquidityNeeded;
            (bool canWithdraw, uint256 maxLPTokensToWithdraw) = inversePlatform.canWithdraw(amountToWithdraw, cviValue);

            if (canWithdraw) {
                inversePlatform.withdraw(amountToWithdraw, type(uint256).max, cviValue);
            } else {
                inversePlatform.withdrawLPTokens(maxLPTokensToWithdraw, cviValue);
            }

            uint256 currHoldings = token.balanceOf(address(this));
            (uint256 currBalance,,,) = totalBalance(cviValue, cviValue);
            uint256 maxHoldings = currBalance * depositHoldingsPercentage / MAX_PERCENTAGE;
            if (currHoldings >= maxHoldings) {
                require(uint168(currHoldings - maxHoldings) == currHoldings - maxHoldings);
                megaThetaVault.deposit(uint168(currHoldings - maxHoldings), cviValue);
            }
        }
    }

    function setFulfiller(address _newFulfiller) external override onlyOwner {
        fulfiller = _newFulfiller;

        emit FulfillerSet(_newFulfiller);
    }

    function setHedgeAdjuster(address _newHedgeAdjuster) external override onlyOwner {
        hedgeAdjuster = _newHedgeAdjuster;

        emit HedgeAdjusterSet(_newHedgeAdjuster);
    }

    function setRewardRouter(IRewardRouter _rewardRouter, address _thetaRewardTracker) external override onlyOwner {
        if (thetaRewardTracker != address(0)) {
            IERC20(address(this)).safeApprove(thetaRewardTracker, 0);
        }

        rewardRouter = _rewardRouter;
        thetaRewardTracker = _thetaRewardTracker;

        IERC20(address(this)).safeApprove(_thetaRewardTracker, type(uint256).max);

        emit RewardRouterSet(address(_rewardRouter), _thetaRewardTracker);
    }

    function setDepositHoldingsPercentage(uint32 _newHoldingsPercentage) external override onlyOwner {
        depositHoldingsPercentage = _newHoldingsPercentage;

        emit DepositHoldingsPercentageSet(_newHoldingsPercentage);
    }

    function setWithdrawFeePercentage(uint32 _newWithdarwFeePercentage) external override onlyOwner {
        withdrawFeePercentage = _newWithdarwFeePercentage;

        emit WithdrawFeePercentageSet(_newWithdarwFeePercentage);
    }

    function totalBalance(uint32 _megaThetaVaultBalanceCVI, uint32 _reversePlatformBalanceCVI) public override view returns (uint256 balance, uint256 inversePlatformLiquidity, uint256 holdings, uint256 megaThetaVaultBalance) {
        holdings = token.balanceOf(address(this));

        (uint256 totalMegaThetaVaultBalance,,) = megaThetaVault.totalBalance(_megaThetaVaultBalanceCVI);
        megaThetaVaultBalance = IERC20(address(megaThetaVault)).totalSupply() == 0 ? 0 : 
            totalMegaThetaVaultBalance * IERC20(address(megaThetaVault)).balanceOf(address(this)) / IERC20(address(megaThetaVault)).totalSupply();

        (uint256 inversePlatformBalance,) = inversePlatform.totalBalance(true, _reversePlatformBalanceCVI);
        inversePlatformLiquidity = IERC20(address(inversePlatform)).totalSupply() == 0 ? 0 : 
            inversePlatformBalance * IERC20(address(inversePlatform)).balanceOf(address(this)) / IERC20(address(inversePlatform)).totalSupply();

        balance = holdings + megaThetaVaultBalance + inversePlatformLiquidity;
    }
}

