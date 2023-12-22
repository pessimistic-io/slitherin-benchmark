// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./IVodkaVault.sol";
import "./IWater.sol";
import "./ISwapRouter.sol";
import "./console.sol";

contract AlpRewardHandler is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== STATE VARIABLES ========== */
    struct RewardDistribution {
        uint256 waterBps;
        uint256 vodkaBps;
        uint256 teamBps;
    }

    IERC20Upgradeable public podToken;
    RewardDistribution public rewardDistribution;
    address public waterVault;
    address public USDC;
    address public CAKE;
    address public uniRouter;
    address teamFeeReceiver;
    address weth;
    uint256 public constant MAX_BPS = 10_000;
    uint256 public accCAKEperTokens;
    uint256 public distributedCAKERewards;

    uint256 public CEIL_SLOPE_1;
    uint256 public CEIL_SLOPE_2;

    uint256 public MAX_INTEREST_SLOPE_1;
    uint256 public MAX_INTEREST_SLOPE_2;
    uint256 totalTeamAmount;
    uint256 totalWaterAmount;
    uint256 minimumSwapAmount;
    mapping(address => uint256) public debtRecordCAKE;
    mapping(address => bool) public canClaimForUser;

    /* ========== MODIFIERS ========== */

    //add a modifier that only allow the vodka vault to call the function
    modifier onlyVodkaVault() {
        require(msg.sender == address(podToken), "Only vodka vault can call this function");
        _;
    }

    modifier zeroAddress(address addr) {
        require(addr != address(0), "Zero address");
        _;
    }
    /* ========== EVENTS ========== */

    event Recovered(address token, uint256 amount);
    event RewardDistributionUpdated(uint256 waterBps, uint256 vodkaBps, uint256 teamBps);
    event UpdateUniRouter(address newUniRouterRouter);
    event SetTeamFeeReceiver(address teamFeeReceiver);

    /* ========== CONSTRUCTOR ========== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _podToken, address _waterVault, address _USDC, address _uniRouter, address _cake) external initializer {
        podToken = IERC20Upgradeable(_podToken);
        waterVault = _waterVault;
        USDC = _USDC;
        uniRouter = _uniRouter;
        CAKE = _cake;
        minimumSwapAmount = 0.2e18;

        __Ownable_init();
        __Pausable_init();
    }

    /* ========== SETTER BY OWNER ========== */
    function setWeth(address _weth) public onlyOwner zeroAddress(_weth) {
        weth = _weth;
    }

    function setMinimumSwapAmount(uint256 _minimumSwapAmount) public onlyOwner {
        minimumSwapAmount = _minimumSwapAmount;
    }

    function setSlopeParams(
        uint256 _ceilSlope1,
        uint256 _ceilSlope2,
        uint256 _max_interest_slope1,
        uint256 _max_interest_slope2
    ) public onlyOwner {
        CEIL_SLOPE_1 = _ceilSlope1;
        CEIL_SLOPE_2 = _ceilSlope2;
        MAX_INTEREST_SLOPE_1 = _max_interest_slope1;
        MAX_INTEREST_SLOPE_2 = _max_interest_slope2;
    }

    function setClaimableForUser(address _account, bool _canClaim) public onlyOwner {
        canClaimForUser[_account] = _canClaim;
    }

    //function to set water vault to a new address
    function setWaterVault(address _waterVault) public onlyOwner zeroAddress(_waterVault) {
        waterVault = _waterVault;
    }

    //function to to teamFeeReceiver emit an event
    function setTeamFeeReceiver(address _teamFeeReceiver) public onlyOwner zeroAddress(_teamFeeReceiver) {
        teamFeeReceiver = _teamFeeReceiver;
        emit SetTeamFeeReceiver(teamFeeReceiver);
    }

    //create a function to set the BPS for the reward distribution
    //this total split will NOT be equal to 100%, only water and owner will
    function setRewardDistribution(uint256 _waterBps, uint256 _vodkaBps, uint256 _teamBps) external onlyOwner {
        require(_waterBps + (_teamBps) == MAX_BPS, "Invalid BPS");
        rewardDistribution = RewardDistribution(_waterBps, _vodkaBps, _teamBps);
        emit RewardDistributionUpdated(_waterBps, _vodkaBps, _teamBps);
    }

    function setuniRouter(address _router) public onlyOwner zeroAddress(_router) {
        uniRouter = _router;
        emit UpdateUniRouter(_router);
    }

    /* ========== VIEWS ========== */

    function totalSupply() public view returns (uint256) {
        return IVodkaVault(address(podToken)).totalSupply();
    }

    function getTotalPosition(address account) public view returns (uint256) {
        return IVodkaVault(address(podToken)).getAggregatePosition(account);
    }

    function pendingRewardsGlp(address account) public view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }
        uint256 UserTotalPODAmount = getTotalPosition(account);
        uint256 pendings = (UserTotalPODAmount * accCAKEperTokens) / 1e18 - debtRecordCAKE[account];
        return (pendings);
    }

    /* ========== CORE FUNCTIONS ========== */

    function getVodkaSplit(uint256 _amount) public view returns (uint256, uint256, uint256) {
        uint256 profit;
        uint256 ownerSplit = (_amount * rewardDistribution.teamBps) / MAX_BPS;
        profit = _amount - ownerSplit;
        uint256 waterShare = _getProfitSplit(profit);
        uint256 waterSplit = (profit * waterShare) / MAX_BPS;
        uint256 vodkaUserSplit = profit - waterSplit;

        return (ownerSplit, waterSplit, vodkaUserSplit);
    }

    function _getProfitSplit(uint256 _amount) internal view returns (uint256) {
        uint256 utilRate = IWater(address(waterVault)).getUtilizationRate();
        uint256 waterSharePercent;
        if (utilRate <= CEIL_SLOPE_1) {
            waterSharePercent = MAX_INTEREST_SLOPE_1;
            //Between 90%-95% utilization - 30% -70%  rewards split to water
        } else if (utilRate <= CEIL_SLOPE_2) {
            waterSharePercent = (MAX_INTEREST_SLOPE_1 +
                ((utilRate - CEIL_SLOPE_1) * (MAX_INTEREST_SLOPE_2 - (MAX_INTEREST_SLOPE_1))) /
                (CEIL_SLOPE_2 - (CEIL_SLOPE_1)));
            //More then 95% utilization - 70%  rewards split to water
        } else {
            waterSharePercent = MAX_INTEREST_SLOPE_2;
        }
        return (waterSharePercent);
    }

    function distributeCAKE(uint256 _amount) public onlyVodkaVault {
        //split rewards to vodka users
        if (totalSupply() > 0) {
            accCAKEperTokens += (_amount * 1e18) / totalSupply();
        }
    }

    function setDebtRecordCAKE(address _account) public onlyVodkaVault {
        uint256 currentUserTotalPODAmount = getTotalPosition(_account);
        debtRecordCAKE[_account] = (currentUserTotalPODAmount * accCAKEperTokens) / 1e18;
    }

    function distributeRewards(uint256 _teamAmount, uint256 _waterAmount) public onlyVodkaVault {
        totalTeamAmount += _teamAmount;
        totalWaterAmount += _waterAmount;
        uint256 totalCake = totalTeamAmount + totalWaterAmount;
        if (totalCake < minimumSwapAmount) {
            return;
        }
        IERC20Upgradeable(CAKE).safeIncreaseAllowance(uniRouter, totalCake);
        uint256 waterAmountOut = _swap(totalWaterAmount);
        uint256 teamAmountOut = _swap(totalTeamAmount);
        totalTeamAmount = 0;
        totalWaterAmount = 0;

        IERC20Upgradeable(USDC).safeTransfer(teamFeeReceiver, teamAmountOut);

        IERC20Upgradeable(USDC).safeApprove(waterVault, waterAmountOut);
        IWater(waterVault).increaseTotalUSDC(waterAmountOut);
    }

    function claimCAKERewards(address _account) public {
        if (canClaimForUser[msg.sender]) {
        } else {
            IVodkaVault(address(podToken)).handleAndCompoundRewards();
        }

        // only vodka vault can call this function
        uint256 CAKERewards = pendingRewardsGlp(_account);
        if (CAKERewards > 0) {
            uint256 currentUserTotalPODAmount = getTotalPosition(_account);
            debtRecordCAKE[_account] = (currentUserTotalPODAmount * accCAKEperTokens) / 1e18;
            distributedCAKERewards += CAKERewards;
            // transfer ETH claim as rewards to msg.sender
            IERC20Upgradeable(CAKE).safeTransfer(_account, CAKERewards);
        }
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(podToken), "Cannot withdraw the staking token");
        IERC20Upgradeable(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function _swap(uint256 _amount) private returns (uint256) {
        uint24 fee = 2500;
        uint24 feeToUSDC = 500;
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(CAKE, fee, weth,  feeToUSDC, USDC), // , feeToUSDC, USDC_NOT_BRIGDED, feeToUSDC, USDC
            recipient: address(this),
            amountIn: _amount,
            amountOutMinimum: 0
        });

        uint256 amountOut = ISwapRouter(uniRouter).exactInput(params);

        return amountOut;
    }

    receive() external payable {}
}

