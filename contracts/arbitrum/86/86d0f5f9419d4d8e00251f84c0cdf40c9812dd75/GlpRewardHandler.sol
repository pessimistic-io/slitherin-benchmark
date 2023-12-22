// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import {IVodkaVault} from "./IVodkaVault.sol";

interface IWater {
    function lend(uint256 _amount) external returns (bool);

    function repayDebt(uint256 leverage, uint256 debtValue) external returns (bool);

    function getTotalDebt() external view returns (uint256);

    function updateTotalDebt(uint256 profit) external returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function balanceOfUSDC() external view returns (uint256);

    function increaseTotalUSDC(uint256 amount) external;
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint deadline;
        uint amountIn;
        uint amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps amountIn of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as ExactInputSingleParams in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint deadline;
        uint amountIn;
        uint amountOutMinimum;
    }

    /// @notice Swaps amountIn of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as ExactInputParams in calldata
    /// @return amountOut The amount of the received token
    function exactInput(ExactInputParams calldata params) external payable returns (uint amountOut);
}

contract GlpRewardHandler is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== STATE VARIABLES ========== */
    struct RewardDistribution {
        uint256 waterBps;
        uint256 vodkaBps;
        uint256 teamBps;
    }

    IERC20Upgradeable public podToken;
    address public waterVault;
    address public USDC;
    address public WETH;
    RewardDistribution public rewardDistribution;
    uint256 public constant MAX_BPS = 10_000;
    uint256 public accWETHperTokens;
    uint256 public distributedWETHRewards;
    address public kyberRouter;
    mapping(address => uint256) public debtRecordWETH;

    uint256 public CEIL_SLOPE_1;
    uint256 public CEIL_SLOPE_2;

    uint256 public MAX_INTEREST_SLOPE_1;
    uint256 public MAX_INTEREST_SLOPE_2;
    address public uniRouter;
    address teamFeeReceiver;
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
    event UpdatekyberRouterRouter(address newkyberRouterRouter);
    event UpdateUniRouter(address newUniRouterRouter);
    event SetTeamFeeReceiver(address teamFeeReceiver);

    /* ========== CONSTRUCTOR ========== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _podToken,
        address _waterVault,
        address _USDC,
        address _uniRouter,
        address _weth
    ) external initializer {
        podToken = IERC20Upgradeable(_podToken);
        waterVault = _waterVault;
        USDC = _USDC;
        uniRouter = _uniRouter;
        WETH = _weth;

        __Ownable_init();
        __Pausable_init();
    }

    /* ========== SETTER BY OWNER ========== */

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
        uint256 pendings = (UserTotalPODAmount * accWETHperTokens) / 1e18 - debtRecordWETH[account];
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
        uint256 utilRate = IVodkaVault(address(waterVault)).getUtilizationRate();
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

    function distributeGlp(uint256 _amount) public onlyVodkaVault {
        //split rewards to vodka users
        if (totalSupply() > 0) {
            accWETHperTokens += (_amount * 1e18) / totalSupply();
        }
    }

    function setDebtRecordWETH(address _account) public onlyVodkaVault {
        uint256 currentUserTotalPODAmount = getTotalPosition(_account);
        debtRecordWETH[_account] = (currentUserTotalPODAmount * accWETHperTokens) / 1e18;
    }

    function distributeRewards(
        uint256 _teamAmount,
        uint256 _waterAmount
    ) public onlyVodkaVault returns (uint256, uint256, uint256) {
        IERC20Upgradeable(WETH).safeTransfer(teamFeeReceiver, _teamAmount);
        _swapWETHtoUSDC(_waterAmount);
    }

    function claimETHRewards(address _account) public {
        address sender;
        IVodkaVault(address(podToken)).handleAndCompoundRewards();
        if (canClaimForUser[msg.sender]) {
            sender = _account;
        } else {
            sender = msg.sender;
        }

        // only vodka vault can call this function
        uint256 WETHRewards = pendingRewardsGlp(sender);
        if (WETHRewards > 0) {
            uint256 currentUserTotalPODAmount = getTotalPosition(sender);
            debtRecordWETH[sender] = (currentUserTotalPODAmount * accWETHperTokens) / 1e18;
            distributedWETHRewards += WETHRewards;
            // transfer ETH claim as rewards to msg.sender
            IERC20Upgradeable(WETH).safeTransfer(sender, WETHRewards);
        }
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(podToken), "Cannot withdraw the staking token");
        IERC20Upgradeable(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function _swapWETHtoUSDC(uint256 _amount) private returns (uint256) {
        IERC20Upgradeable(WETH).approve(address(uniRouter), _amount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amount,
            //@todo have access to the oracle in gmx, can utilize that to get the price?
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = ISwapRouter(uniRouter).exactInputSingle(params);

        IERC20Upgradeable(USDC).safeApprove(waterVault, amountOut);
        IWater(waterVault).increaseTotalUSDC(amountOut);

        return (amountOut);
    }
}

