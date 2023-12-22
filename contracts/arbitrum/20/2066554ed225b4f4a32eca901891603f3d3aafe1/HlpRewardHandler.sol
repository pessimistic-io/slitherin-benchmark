// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
//import IWater
import "./IWater.sol";

import { IRumVault } from "./IRumVault.sol";
import { IHlpRewardHandler } from "./IHlpRewardHandler.sol";
import { IRewarder } from "./IRewarder.sol";

import "./console.sol";

contract HlpRewardHandler is IHlpRewardHandler, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== STATE VARIABLES ========== */
    uint256 public constant MAX_BPS = 10_000;
    uint256 public accUSDCperTokens;
    uint256 public distributedUSDCRewards;
    uint256 public teamRewardBps;
    mapping(address => uint256) public debtRecordUSDC;

    uint256 public CEIL_SLOPE_1;
    uint256 public CEIL_SLOPE_2;

    uint256 public MAX_INTEREST_SLOPE_1;
    uint256 public MAX_INTEREST_SLOPE_2;
    address public waterVault;
    address public USDC;
    IERC20Upgradeable public podToken;

    uint256[50] private __gaps;
    address public usdcRewarder;

    /* ========== MODIFIERS ========== */
    //add a modifier that only allow the rum vault to call the function
    modifier onlyRumVault() {
        require(msg.sender == address(podToken), "Only rum vault");
        _;
    }

    modifier zeroAddress(address addr) {
        require(addr != address(0), "Zero address");
        _;
    }
    /* ========== EVENTS ========== */

    event Recovered(address token, uint256 amount);
    event RewardDistributionUpdated(uint256 teamBps);
    event RewardDistributed(uint256 usdcRewards, uint256 toOwner, uint256 toWater, uint256 toRumUsers);

    /* ========== CONSTRUCTOR ========== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _podToken, address _waterVault, address _USDC) external initializer {
        podToken = IERC20Upgradeable(_podToken);
        waterVault = _waterVault;
        USDC = _USDC;
        __Ownable_init();
        __Pausable_init();
        // setSlopeParams(90 * 1e17, 95 * 1e17, 3_000, 7_000);
        // setTeamRewardBps(500);
    }

    // function to set teamRewardBps
    function setTeamRewardBps(uint256 _teamRewardBps) public onlyOwner {
        require(_teamRewardBps < MAX_BPS, "Invalid team reward bps");
        teamRewardBps = _teamRewardBps;
        emit RewardDistributionUpdated(teamRewardBps);
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

    //function to set water vault to a new address
    function setWaterVault(address _waterVault) public onlyOwner zeroAddress(_waterVault) {
        waterVault = _waterVault;
    }

    //function setRumVault to a new address
    function setRumVault(address _rumVault) public onlyOwner zeroAddress(_rumVault) {
        podToken = IERC20Upgradeable(_rumVault);
    }

    function setUSDCRewarder(address _usdcRewarder) public onlyOwner {
        usdcRewarder = _usdcRewarder;
    }

    /* ========== VIEWS ========== */

    function totalSupply() public view returns (uint256) {
        return IERC20Upgradeable(address(podToken)).totalSupply();
    }

    function getTotalPosition(address account) public view returns (uint256) {
        return IRumVault(address(podToken)).getAggregatePosition(account);
    }

    function pendingRewardsUSDC(address account) public view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }
        uint256 UserTotalPODAmount = getTotalPosition(account);

        console.log("UserTotalPODAmount", UserTotalPODAmount);
        console.log("accUSDCperTokens", accUSDCperTokens);
        console.log("debtRecordUSDC[account]", debtRecordUSDC[account]);
        console.log("UserTotalPODAmount * accUSDCperTokens", UserTotalPODAmount * accUSDCperTokens);

        uint256 pendings = (UserTotalPODAmount * accUSDCperTokens) / 1e18 - debtRecordUSDC[account];
        console.log("pendings", pendings);
        return (pendings);
    }

    function getPendingUSDCRewards() public view returns (uint256) {
        return IRewarder(usdcRewarder).pendingReward(address(podToken));
    }

    /* ========== CORE FUNCTIONS ========== */

    function getRumSplit(uint256 _amount) public view returns (uint256, uint256, uint256) {
        uint256 profit;
        uint256 ownerSplit = (_amount * teamRewardBps) / MAX_BPS;
        profit = _amount - ownerSplit;
        uint256 waterShare = _getProfitSplit();
        uint256 waterSplit = (profit * waterShare) / MAX_BPS;
        uint256 rumUserSplit = profit - waterSplit;

        return (ownerSplit, waterSplit, rumUserSplit);
    }

    function _getProfitSplit() internal view returns (uint256) {
        uint256 utilRate = IRumVault(address(podToken)).getUtilizationRate();
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

    function distributeUSDC(uint256 _amount) internal {
        //split rewards to rum users
        if (totalSupply() > 0) {
            console.log("totalSupply()", totalSupply());
            console.log("_amount", _amount);
            console.log("accUSDCperTokens", accUSDCperTokens);
            accUSDCperTokens += (_amount * 1e18) / totalSupply();
            console.log("accUSDCperTokens", accUSDCperTokens);
        }
    }

    function setDebtRecordUSDC(address _account) public onlyRumVault {
        uint256 currentUserTotalPODAmount = getTotalPosition(_account);
        debtRecordUSDC[_account] = (currentUserTotalPODAmount * accUSDCperTokens) / 1e18;
    }

    function distributeRewards(uint256 _teamAmount, uint256 _waterAmount) internal {
        IERC20Upgradeable(USDC).safeTransfer(owner(), _teamAmount);
        IWater(waterVault).increaseTotalUSDC(_waterAmount);
    }

    function claimUSDCRewards(address _account) public {
        address sender;
        if (msg.sender == address(podToken)) {
            sender = _account;
        } else {
            sender = msg.sender;
        }

        compoundRewards();

        uint256 USDCRewards = pendingRewardsUSDC(sender);
        console.log("USDCRewards", USDCRewards);
        uint256 bal = IERC20Upgradeable(USDC).balanceOf(address(this));
        console.log("bal", bal);

        if (USDCRewards > 0) {
            uint256 currentUserTotalPODAmount = getTotalPosition(sender);
            debtRecordUSDC[sender] = (currentUserTotalPODAmount * accUSDCperTokens) / 1e18;
            distributedUSDCRewards += USDCRewards;
            IERC20Upgradeable(USDC).safeTransfer(sender, USDCRewards);
        }
    }

    function compoundRewards() public {
        // if (getPendingUSDCRewards() < 1e6) {
        //     return;
        // }
        address[] memory pools = new address[](2);
        pools[0] = 0xbE8f8AF5953869222eA8D39F1Be9d03766010B1C;
        pools[1] = 0x92E586B8D4Bf59f4001604209A292621c716539a;

        address[] memory nestedAddresses1 = new address[](3);
        nestedAddresses1[0] = 0x665099B3e59367f02E5f9e039C3450E31c338788;
        nestedAddresses1[1] = 0xCE3C078282df113eFc3D816E83Ca70f4c19d9daB;
        nestedAddresses1[2] = 0x6D2c18B559C5343CB0703bB55AADB5f22152cC32;

        address[] memory nestedAddresses2 = new address[](3);
        nestedAddresses2[0] = 0xB698829C4C187C85859AD2085B24f308fC1195D3;
        nestedAddresses2[1] = 0x94c22459b145F012F1c6791F2D729F7a22c44764;
        nestedAddresses2[2] = 0xbEDd351c62111FB7216683C2A26319743a06F273;

        address[][] memory rewarder = new address[][](2);
        rewarder[0] = nestedAddresses1;
        rewarder[1] = nestedAddresses2;

        uint256 usdcRewards = IRumVault(address(podToken)).handleAndCompoundRewards(pools, rewarder);
        console.log("usdcRewards", usdcRewards);

        (uint256 toOwner, uint256 toWater, uint256 toRumUsers) = getRumSplit(usdcRewards);
        console.log("toRumUsers", toRumUsers);
        console.log("toOwner", toOwner);
        console.log("toWater", toWater);

        distributeUSDC(toRumUsers);
        distributeRewards(toOwner, toWater);

        emit RewardDistributed(usdcRewards, toOwner, toWater, toRumUsers);
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(podToken), "Cannot withdraw the staking token");
        IERC20Upgradeable(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    //approve usdc.e to water
    function approveUSDC() public onlyOwner {
        IERC20Upgradeable(USDC).safeApprove(waterVault, type(uint256).max);
    }
}

