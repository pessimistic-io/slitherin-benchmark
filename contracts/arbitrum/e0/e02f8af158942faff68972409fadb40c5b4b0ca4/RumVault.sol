// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { SafeERC20Upgradeable, IERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ERC20BurnableUpgradeable } from "./ERC20BurnableUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { MathUpgradeable } from "./MathUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IMasterChef } from "./IMasterChef.sol";
import { ICalculator } from "./ICalculator.sol";
import { ILiquidityHandler } from "./ILiquidityHandler.sol";
import { IHLPStaking } from "./IHLPStaking.sol";
import { IWater } from "./IWater.sol";
import { ICompounder } from "./ICompounder.sol";
import { IHlpRewardHandler } from "./IHlpRewardHandler.sol";
import { IRumVault } from "./IRumVault.sol";
import { IVester } from "./IVester.sol";
import { IHMXStaking } from "./IHMXStaking.sol";

contract RumVault is IRumVault, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, ERC20BurnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;
    using MathUpgradeable for uint128;

    uint256 public MCPID;
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant DENOMINATOR = 1_000;
    uint256 public constant DECIMAL = 1e18;

    uint256[] public tokenIds;
    address[] public allUsers;

    FeeConfiguration public feeConfiguration;
    StrategyAddresses public strategyAddresses;
    DebtAdjustmentValues public debtAdjustmentValues;
    KeeperInfo public keeperInfo;
    LeverageParams public leverageParams;
    HMXVesting public hmxVesting;

    mapping(address => PositionInfo[]) public positionInfo;
    mapping(address => bool) public allowedSenders;
    mapping(address => bool) public burner;
    mapping(address => bool) private isUser;
    mapping(uint256 => DepositRecord) public depositRecord;
    mapping(uint256 => WithdrawRecord) public withdrawRecord;
    mapping(address => mapping(uint256 => bool)) public inCloseProcess;
    mapping(address => uint256[]) public openOrderIds;
    mapping(address => uint256[]) public closeOrderIds;

    uint256[50] private __gaps;

    uint256 public mFeePercent;
    address public mFeeReceiver;

    modifier InvalidID(uint256 positionId, address user) {
        require(positionId < positionInfo[user].length, "RUM: positionID is not valid");
        _;
    }

    modifier onlyBurner() {
        require(burner[msg.sender], "Not allowed to burn");
        _;
    }

    modifier onlyKeeper() {
        require(msg.sender == keeperInfo.keeper, "Not keeper");
        _;
    }
    //only hlpRewardHandler
    modifier onlyhlpRewardHandler() {
        require(msg.sender == strategyAddresses.hlpRewardHandler, "Only hlp reward handler");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        debtAdjustmentValues.time = block.timestamp;

        __Ownable_init();
        __Pausable_init();
        __ERC20_init("RUM-POD", "RUM-POD");
    }

    /** ----------- Change onlyOwner functions ------------- */

    function setMFeePercent(uint256 _mFeePercent, address _mFeeReceiver) external onlyOwner {
        require(_mFeePercent <= 10000, "Invalid mFeePercent");
        mFeeReceiver = _mFeeReceiver;
        mFeePercent = _mFeePercent;
        emit SetManagementFee(_mFeePercent, _mFeeReceiver);
    }

    function setAllowed(address _sender, bool _allowed) external onlyOwner {
        allowedSenders[_sender] = _allowed;
        emit SetAllowedSenders(_sender, _allowed);
    }

    function setBurner(address _burner, bool _allowed) external onlyOwner {
        burner[_burner] = _allowed;
        emit SetBurner(_burner, _allowed);
    }

    function setMCPID(uint256 _MCPID) external onlyOwner {
        MCPID = _MCPID;
        emit SetMCPID(_MCPID);
    }

    function setLeverageParams(
        uint256 _maxLeverage,
        uint256 _minLeverage,
        uint256 _DTVLimit,
        uint256 _DTVSlippage,
        uint256 _debtValueRatio,
        uint256 _timeAdjustment
    ) public onlyOwner {
        require(_maxLeverage >= _minLeverage, "Max leverage must be greater than min leverage");
        require(_DTVSlippage <= 1000, "DTVSlippage must be less than 1000");
        require(_debtValueRatio <= 1e18, "Debt value ratio must be less than 1");

        leverageParams.maxLeverage = _maxLeverage;
        leverageParams.minLeverage = _minLeverage;

        leverageParams.DTVLimit = _DTVLimit;
        leverageParams.DTVSlippage = _DTVSlippage;

        leverageParams.debtAdjustmentInterval = _timeAdjustment;
        debtAdjustmentValues.debtValueRatio = _debtValueRatio;

        emit DTVLimitSet(_DTVLimit, leverageParams.DTVSlippage);
        emit UpdateMaxAndMinLeverage(_maxLeverage, _minLeverage);
    }

    function setProtocolFee(
        address _feeReceiver,
        uint256 _withdrawalFee,
        address _waterFeeReceiver,
        uint256 _liquidatorsRewardPercentage,
        uint256 _fixedFeeSplit,
        uint256 _hlpFee,
        uint256 _keeperFee,
        uint256 _slippageTolerance
    ) external onlyOwner {
        feeConfiguration.feeReceiver = _feeReceiver;
        feeConfiguration.withdrawalFee = _withdrawalFee;
        feeConfiguration.waterFeeReceiver = _waterFeeReceiver;
        feeConfiguration.liquidatorsRewardPercentage = _liquidatorsRewardPercentage;
        feeConfiguration.fixedFeeSplit = _fixedFeeSplit;
        feeConfiguration.hlpFee = _hlpFee;
        keeperInfo.keeperFee = _keeperFee;
        feeConfiguration.slippageTolerance = _slippageTolerance;

        emit ProtocolFeeChanged(
            _feeReceiver,
            _withdrawalFee,
            _waterFeeReceiver,
            _liquidatorsRewardPercentage,
            _fixedFeeSplit,
            _keeperFee,
            _slippageTolerance
        );
    }

    function setHMXVesting(address hmxStaking, address vester, address hmx) external onlyOwner {
        hmxVesting.hmxStaking = hmxStaking;
        hmxVesting.vester = vester;
        hmxVesting.hmx = hmx;

        emit HMXVestingChanged(hmxStaking, vester, hmx);
    }

    function setStrategyAddresses(
        address _USDC,
        address _hmxCalculator,
        address _hlpLiquidityHandler,
        address _hlpStaking,
        address _hlpCompounder,
        address _water,
        address _MasterChef,
        address _hlp,
        address _hlpRewardHandler,
        address _keeper
    ) external onlyOwner {
        //check for zero address
        strategyAddresses.USDC = _USDC;
        strategyAddresses.hmxCalculator = _hmxCalculator;
        strategyAddresses.hlpLiquidityHandler = _hlpLiquidityHandler;
        strategyAddresses.hlpStaking = _hlpStaking;
        strategyAddresses.hlpCompounder = _hlpCompounder;
        strategyAddresses.water = _water;
        strategyAddresses.MasterChef = _MasterChef;
        strategyAddresses.hlp = _hlp;
        strategyAddresses.hlpRewardHandler = _hlpRewardHandler;
        keeperInfo.keeper = _keeper;

        emit StrategyContractsChanged(
            _USDC,
            _hmxCalculator,
            _hlpLiquidityHandler,
            _hlpStaking,
            _hlpCompounder,
            _water,
            _MasterChef,
            _hlp,
            _hlpRewardHandler,
            _keeper
        );
    }

    //     function updateDebtAdjustment() external onlyOwner {
    //         require(getUtilizationRate() > (leverageParams.DTVLimit), "Utilization rate is not greater than DTVLimit");
    //         require(
    //             block.timestamp - debtAdjustmentValues.time > leverageParams.debtAdjustmentUpdateInterval,
    //             "Time difference is not greater than 72 hours"
    //         );
    //
    //         debtAdjustmentValues.debtAdjustment =
    //             debtAdjustmentValues.debtAdjustment +
    //             (debtAdjustmentValues.debtAdjustment * debtAdjustmentValues.debtValueRatio) /
    //             1e18;
    //         debtAdjustmentValues.time = block.timestamp;
    //     }

    //     function pause() external onlyOwner {
    //         _pause();
    //     }
    //
    //     function unpause() external onlyOwner {
    //         _unpause();
    //     }

    function vestEsHmx(uint256 _amount) external onlyOwner {
        IHMXStaking(hmxVesting.hmxStaking).vestEsHmx(_amount, 31536000);
    }

    function claimVesting(uint256[] calldata indexes) external onlyOwner {
        IVester(hmxVesting.vester).claim(indexes);
        IERC20Upgradeable(hmxVesting.hmx).transfer(
            feeConfiguration.feeReceiver,
            IERC20Upgradeable(hmxVesting.hmx).balanceOf(address(this))
        );
    }

    function cancelVesting(uint256 index) external onlyOwner {
        IVester(hmxVesting.vester).abort(index);
    }

    function getCurrentLeverageAmount(uint256 _positionID, address _user) public view returns (uint256) {
        PositionInfo memory _positionInfo = positionInfo[_user][_positionID];
        uint256 previousDA = _positionInfo.debtAdjustmentValue;
        uint256 userLeverageAmount = _positionInfo.leverageAmount;
        if (debtAdjustmentValues.debtAdjustment > _positionInfo.debtAdjustmentValue) {
            userLeverageAmount = userLeverageAmount.mulDiv(debtAdjustmentValues.debtAdjustment, previousDA);
        }
        return (userLeverageAmount);
    }

    function getHLPPrice(bool _maximise) public view returns (uint256) {
        return
            ICalculator(strategyAddresses.hmxCalculator).getHLPPrice(
                ICalculator(strategyAddresses.hmxCalculator).getAUME30(_maximise),
                IERC20Upgradeable(strategyAddresses.hlp).totalSupply()
            );
        //HLP Price in e12
    }

    function getAllUsers() external view returns (address[] memory) {
        return allUsers;
    }

    function getNumbersOfPosition(address _user) external view returns (uint256) {
        return positionInfo[_user].length;
    }

    function getUtilizationRate() public view returns (uint256) {
        uint256 totalWaterDebt = IWater(strategyAddresses.water).totalDebt();
        return totalWaterDebt == 0 ? 0 : totalWaterDebt.mulDiv(DECIMAL, IWater(strategyAddresses.water).balanceOfUSDC() + totalWaterDebt);
    }

    function getPosition(
        uint256 _positionID,
        address _user,
        uint256 hlpPrice
    ) public view returns (uint256, uint256, uint256, uint256, uint256) {
        PositionInfo memory _positionInfo = positionInfo[_user][_positionID];
        if (_positionInfo.isClosed || _positionInfo.isLiquidated) return (0, 0, 0, 0, 0);

        uint256 currentPositionValue = _convertHLPToUSDC(_positionInfo.position, hlpPrice);

        uint256 OriginalLeverageAmount = _positionInfo.leverageAmount;

        uint256 currentDTV = OriginalLeverageAmount.mulDiv(DECIMAL, currentPositionValue);

        uint256 leveageAmountWithDA = getCurrentLeverageAmount(_positionID, _user);

        uint256 currentDTVWithDA = leveageAmountWithDA.mulDiv(DECIMAL, currentPositionValue);

        return (currentDTV, OriginalLeverageAmount, currentPositionValue, currentDTVWithDA, leveageAmountWithDA);
    }

    /** ----------- User functions ------------- */
    function handleAndCompoundRewards(
        address[] calldata pools,
        address[][] calldata rewarder
    ) external onlyhlpRewardHandler returns (uint256 amount) {
        uint256 balanceBefore = IERC20Upgradeable(strategyAddresses.USDC).balanceOf(address(this));

        ICompounder(strategyAddresses.hlpCompounder).compound(pools, rewarder, 0, 0, tokenIds);

        uint256 balanceAfter = IERC20Upgradeable(strategyAddresses.USDC).balanceOf(address(this));

        uint256 usdcRewards = balanceAfter - balanceBefore;

        IERC20Upgradeable(strategyAddresses.USDC).transfer(strategyAddresses.hlpRewardHandler, usdcRewards);

        emit USDCHarvested(usdcRewards);

        return (usdcRewards);
    }

    function requestOpenPosition(uint256 _amount, uint16 _leverage) external payable whenNotPaused returns (uint256) {
        require(_leverage >= leverageParams.minLeverage && _leverage <= leverageParams.maxLeverage, "RUM: Invalid leverage");
        require(_amount > 0, "RUM: amount must be greater than zero");
        require(msg.value >= keeperInfo.keeperFee + feeConfiguration.hlpFee, "RUM: fee not enough");

        IERC20Upgradeable(strategyAddresses.USDC).safeTransferFrom(msg.sender, address(this), _amount);
        // get leverage amount
        uint256 leveragedAmount = _amount.mulDiv(_leverage, DENOMINATOR) - _amount;
        bool status = IWater(strategyAddresses.water).lend(leveragedAmount);
        require(status, "Water: Lend failed");
        // add leverage amount to amount
        uint256 totalPositionValue = _amount + leveragedAmount;

        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.hlpLiquidityHandler, totalPositionValue);

        //minOut is totalPositionValue * hlpPrice * sliipage
        uint256 minOut = ((totalPositionValue * 1e24) / getHLPPrice(true)).mulDiv((MAX_BPS - feeConfiguration.slippageTolerance), MAX_BPS);

        uint256 orderId = ILiquidityHandler(strategyAddresses.hlpLiquidityHandler).createAddLiquidityOrder{
            value: feeConfiguration.hlpFee
        }(
            strategyAddresses.USDC,
            totalPositionValue,
            minOut, //minOut
            msg.value,
            false,
            false
        );

        DepositRecord storage dr = depositRecord[orderId];
        dr.leverageAmount = leveragedAmount;
        dr.depositedAmount = _amount;
        // dr.feesPaid = msg.value;
        dr.minOut = minOut;
        dr.user = msg.sender;
        dr.leverageMultiplier = _leverage;
        openOrderIds[msg.sender].push(orderId);

        payable(keeperInfo.keeper).transfer(keeperInfo.keeperFee);

        emit RequestedOpenPosition(msg.sender, _amount, block.timestamp, orderId);

        return (orderId);
    }

    //@dev backend listen to the event of LogRefund and call this function
    function fulfillOpenCancellation(uint256 orderId) public onlyKeeper returns (bool) {
        DepositRecord storage dr = depositRecord[orderId];
        require(dr.isOrderCompleted == false, "RUM: order already fulfilled");
        //refund the amount to user
        IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(dr.user, dr.depositedAmount);
        //refund the leverage to water
        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.water, dr.leverageAmount);
        IWater(strategyAddresses.water).repayDebt(dr.leverageAmount, dr.leverageAmount);
        //refund the fee to user
        dr.isOrderCompleted = true;
        //@add an item in the DepositRecord to show that the event is cancelled.
        emit OpenPositionCancelled(dr.user, dr.depositedAmount, block.timestamp, orderId);

        return true;
    }

    //@dev backend listen to the event of LogExecuteLiquidityOrder and call this function
    function fulfillOpenPosition(uint256 orderId, uint256 _actualOut) public onlyKeeper returns (bool) {
        //require that orderId doesnt not exist
        DepositRecord storage dr = depositRecord[orderId];
        require(dr.isOrderCompleted == false, "RUM: order already fulfilled");

        uint256 expectedOut = _convertUSDCToHLP(dr.depositedAmount + dr.leverageAmount, getHLPPrice(true));

        require(
            isWithinSlippage(_actualOut, expectedOut, feeConfiguration.slippageTolerance),
            "RUM:  _actualOut not within slippage tolerance"
        );

        dr.receivedHLP = _actualOut;
        address user = dr.user;

        IHlpRewardHandler(strategyAddresses.hlpRewardHandler).claimUSDCRewards(user);

        PositionInfo memory _positionInfo = PositionInfo({
            deposit: dr.depositedAmount,
            position: dr.receivedHLP,
            buyInPrice: getHLPPrice(true),
            leverageAmount: dr.leverageAmount,
            liquidator: address(0),
            user: dr.user,
            positionId: uint32(positionInfo[user].length),
            leverageMultiplier: dr.leverageMultiplier,
            isLiquidated: false,
            isClosed: false,
            debtAdjustmentValue: debtAdjustmentValues.debtAdjustment
        });
        //frontend helper to fetch all users and then their userInfo
        if (isUser[user] == false) {
            isUser[user] = true;
            allUsers.push(user);
        }
        positionInfo[user].push(_positionInfo);
        // mint gmx shares to user
        _mint(user, dr.receivedHLP);

        dr.isOrderCompleted = true;

        IHlpRewardHandler(strategyAddresses.hlpRewardHandler).setDebtRecordUSDC(dr.user);

        emit FulfilledOpenPosition(
            user,
            _positionInfo.deposit,
            dr.receivedHLP,
            block.timestamp,
            _positionInfo.positionId,
            getHLPPrice(true),
            orderId
        );

        return true;
    }

    function requestClosePosition(uint32 _positionID) external payable InvalidID(_positionID, msg.sender) nonReentrant {
        PositionInfo storage _positionInfo = positionInfo[msg.sender][_positionID];
        require(!_positionInfo.isLiquidated, "RUM: position is liquidated");
        require(msg.sender == _positionInfo.user, "RUM: not allowed to close position");
        require(!inCloseProcess[msg.sender][_positionID], "RUM: close position request already ongoing");
        require(msg.value >= keeperInfo.keeperFee + feeConfiguration.hlpFee, "RUM: fee not enough");

        (, , , uint256 currentDTVWithDA, ) = getPosition(_positionID, msg.sender, getHLPPrice(false));

        if (currentDTVWithDA >= (leverageParams.DTVLimit * leverageParams.DTVSlippage) / 1000) {
            revert("Wait for liquidation");
        }

        uint256 withdrawAsssetAmount;
        uint256 orderId;

        withdrawAsssetAmount = _positionInfo.position;

        IHLPStaking(strategyAddresses.hlpStaking).withdraw(_positionInfo.position);

        IERC20Upgradeable(strategyAddresses.hlp).safeIncreaseAllowance(strategyAddresses.hlpLiquidityHandler, _positionInfo.position);

        uint256 minOut = (withdrawAsssetAmount * getHLPPrice(true)).mulDiv((MAX_BPS - feeConfiguration.slippageTolerance), MAX_BPS) / 1e24;

        orderId = ILiquidityHandler(strategyAddresses.hlpLiquidityHandler).createRemoveLiquidityOrder{ value: feeConfiguration.hlpFee }(
            strategyAddresses.USDC,
            withdrawAsssetAmount,
            minOut, //minOut
            msg.value,
            false
        );

        WithdrawRecord storage wr = withdrawRecord[orderId];

        wr.user = msg.sender;
        wr.positionID = _positionID;
        wr.minOut = minOut;
        inCloseProcess[msg.sender][_positionID] = true;
        closeOrderIds[msg.sender].push(orderId);
        payable(keeperInfo.keeper).transfer(keeperInfo.keeperFee);

        emit RequestedClosePosition(msg.sender, withdrawAsssetAmount, block.timestamp, orderId, _positionID);
    }

    function fulfillCloseCancellation(uint256 orderId) public onlyKeeper returns (bool) {
        WithdrawRecord storage wr = withdrawRecord[orderId];
        PositionInfo storage _positionInfo = positionInfo[wr.user][wr.positionID];
        require(wr.isOrderCompleted == false, "RUM: order already fulfilled");

        uint256 reDepositAmount = _positionInfo.position;
        //redeposit the position to hlp staking
        IERC20Upgradeable(strategyAddresses.hlp).approve(strategyAddresses.hlpStaking, reDepositAmount);
        IHLPStaking(strategyAddresses.hlpStaking).deposit(address(this), reDepositAmount);

        inCloseProcess[wr.user][wr.positionID] = false;
        wr.isOrderCompleted = true;

        emit ClosePositionCancelled(wr.user, _positionInfo.position, block.timestamp, orderId, wr.positionID);

        return true;
    }

    function fulfillClosePosition(uint256 _orderId, uint256 _returnedUSDC) public onlyKeeper returns (bool) {
        WithdrawRecord storage wr = withdrawRecord[_orderId];
        PositionInfo storage _positionInfo = positionInfo[wr.user][wr.positionID];
        require(wr.isOrderCompleted == false, "RUM: order already fulfilled");

        require(
            isWithinSlippage(
                _returnedUSDC,
                _convertHLPToUSDC(_positionInfo.position, getHLPPrice(false)),
                feeConfiguration.slippageTolerance
            ),
            "RUM: returnedUSDC not within slippage tolerance"
        );

        ExtraData memory extraData;
        require(inCloseProcess[wr.user][wr.positionID], "Rum: close position request not ongoing");

        IHlpRewardHandler(strategyAddresses.hlpRewardHandler).claimUSDCRewards(wr.user);

        _handlePODToken(wr.user, _positionInfo.position);

        (, , , , uint256 leverageAmountWihtDA) = getPosition(wr.positionID, wr.user, getHLPPrice(false));

        wr.fullDebtValue = leverageAmountWihtDA;
        wr.returnedUSDC = _returnedUSDC;

        extraData.positionPreviousValue = _convertHLPToUSDC(_positionInfo.position, _positionInfo.buyInPrice);
        extraData.returnedValue = _returnedUSDC;
        extraData.orderId = _orderId;

        if (_returnedUSDC > extraData.positionPreviousValue) {
            extraData.profits = _returnedUSDC - extraData.positionPreviousValue;
        }

        uint256 waterRepayment;
        (uint256 waterProfits, uint256 mFee, uint256 leverageUserProfits) = _getProfitSplit(
            extraData.profits,
            _positionInfo.leverageMultiplier
        );

        if (extraData.returnedValue < (wr.fullDebtValue + waterProfits + mFee)) {
            _positionInfo.liquidator = msg.sender;
            _positionInfo.isLiquidated = true;
            waterRepayment = extraData.returnedValue;
        } else {
            extraData.toLeverageUser = (extraData.returnedValue - wr.fullDebtValue - extraData.profits) + leverageUserProfits;
            waterRepayment = extraData.returnedValue - extraData.toLeverageUser - waterProfits - mFee;
        }

        _positionInfo.isClosed = true;

        if (waterProfits > 0) {
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(feeConfiguration.waterFeeReceiver, waterProfits);
        }
        if (mFee > 0) {
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(mFeeReceiver, mFee);
        }

        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.water, waterRepayment);
        IWater(strategyAddresses.water).repayDebt(_positionInfo.leverageAmount, waterRepayment);

        _positionInfo.position = 0;
        _positionInfo.leverageAmount = 0;

        if (_positionInfo.isLiquidated) {
            return (false);
        }

        uint256 amountAfterFee;
        if (feeConfiguration.withdrawalFee > 0) {
            uint256 fee = extraData.toLeverageUser.mulDiv(feeConfiguration.withdrawalFee, MAX_BPS);
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(feeConfiguration.feeReceiver, fee);
            amountAfterFee = extraData.toLeverageUser - fee;
        } else {
            amountAfterFee = extraData.toLeverageUser;
        }

        IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(wr.user, amountAfterFee);

        IHlpRewardHandler(strategyAddresses.hlpRewardHandler).setDebtRecordUSDC(wr.user);

        emit FulfilledClosePosition(
            wr.user,
            extraData.toLeverageUser,
            block.timestamp,
            _positionInfo.position,
            leverageUserProfits,
            getHLPPrice(true),
            wr.positionID,
            extraData.orderId
        );

        return true;
    }

    function requestLiquidatePosition(address _user, uint256 _positionID) external payable nonReentrant {
        PositionInfo storage _positionInfo = positionInfo[_user][_positionID];

        //update leverage Amount with DA
        require(!_positionInfo.isLiquidated, "RUM: Already liquidated");
        require(_positionInfo.user != address(0), "RUM: liquidation request does not exist");
        require(!inCloseProcess[_user][_positionID], "RUM: close position request already ongoing");
        require(msg.value >= keeperInfo.keeperFee + feeConfiguration.hlpFee, "RUM: fee not enough");

        (, , , uint256 currentDTVWithDA, ) = getPosition(_positionID, _user, getHLPPrice(false));

        require(currentDTVWithDA >= (leverageParams.DTVLimit * leverageParams.DTVSlippage) / 1000, "Liquidation threshold not reached yet");

        IHLPStaking(strategyAddresses.hlpStaking).withdraw(_positionInfo.position);
        IERC20Upgradeable(strategyAddresses.hlp).approve(strategyAddresses.hlpLiquidityHandler, _positionInfo.position);

        uint256 minOut = (_positionInfo.position * getHLPPrice(true)).mulDiv((MAX_BPS - feeConfiguration.slippageTolerance), MAX_BPS) /
            1e24;
        uint256 orderId = ILiquidityHandler(strategyAddresses.hlpLiquidityHandler).createRemoveLiquidityOrder{
            value: feeConfiguration.hlpFee
        }(
            strategyAddresses.USDC,
            _positionInfo.position,
            minOut, //minOut
            msg.value,
            false
        );

        WithdrawRecord storage wr = withdrawRecord[orderId];

        inCloseProcess[_user][_positionID] = true;
        wr.user = _user;
        wr.positionID = _positionID;
        wr.isLiquidation = true;
        wr.liquidator = msg.sender;

        payable(keeperInfo.keeper).transfer(keeperInfo.keeperFee);
    }

    function fulfillLiquidation(uint256 _orderId, uint256 _returnedUSDC) external nonReentrant onlyKeeper {
        WithdrawRecord storage wr = withdrawRecord[_orderId];
        PositionInfo storage _positionInfo = positionInfo[wr.user][wr.positionID];
        require(!_positionInfo.isLiquidated, "RUM: Already liquidated");

        IHlpRewardHandler(strategyAddresses.hlpRewardHandler).claimUSDCRewards(wr.user);

        (, , , , uint256 leverageAmountWihtDA) = getPosition(wr.positionID, wr.user, getHLPPrice(false));

        _handlePODToken(wr.user, _positionInfo.position);

        wr.returnedUSDC = _returnedUSDC;

        uint256 liquidatorReward;
        if (wr.returnedUSDC >= leverageAmountWihtDA) {
            wr.returnedUSDC -= leverageAmountWihtDA;

            liquidatorReward = wr.returnedUSDC.mulDiv(feeConfiguration.liquidatorsRewardPercentage, MAX_BPS);
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(wr.liquidator, liquidatorReward);

            uint256 leftovers = wr.returnedUSDC - liquidatorReward;

            IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.water, leftovers + leverageAmountWihtDA);
            IWater(strategyAddresses.water).repayDebt(_positionInfo.leverageAmount, leftovers + leverageAmountWihtDA);
        } else {
            IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.water, wr.returnedUSDC);
            IWater(strategyAddresses.water).repayDebt(_positionInfo.leverageAmount, wr.returnedUSDC);
        }

        uint256 outputAmount = 0;

        _positionInfo.liquidator = msg.sender;
        _positionInfo.isLiquidated = true;
        _positionInfo.position = 0;

        IHlpRewardHandler(strategyAddresses.hlpRewardHandler).setDebtRecordUSDC(wr.user);

        emit Liquidated(wr.user, wr.positionID, msg.sender, outputAmount, liquidatorReward, _orderId);
    }

    /** ----------- Token functions ------------- */

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        require(allowedSenders[from] || allowedSenders[to] || allowedSenders[spender], "ERC20: transfer not allowed");
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        address ownerOf = _msgSender();
        require(allowedSenders[ownerOf] || allowedSenders[to], "ERC20: transfer not allowed");
        _transfer(ownerOf, to, amount);
        return true;
    }

    function burn(uint256 amount) public override(ERC20BurnableUpgradeable, IRumVault) onlyBurner {
        _burn(_msgSender(), amount);
    }

    /** ----------- Internal functions ------------- */
    function _getProfitSplit(uint256 _profit, uint256 _leverage) internal view returns (uint256, uint256, uint256) {
        if (_profit == 0) {
            return (0, 0, 0);
        }
        uint256 split = (feeConfiguration.fixedFeeSplit * _leverage + (feeConfiguration.fixedFeeSplit * MAX_BPS)) / 100;
        uint256 toWater = (_profit * split) / MAX_BPS;
        uint256 mFee = (_profit * mFeePercent) / MAX_BPS;
        uint256 toVodkaV2User = _profit - (toWater + mFee);

        return (toWater, mFee, toVodkaV2User);
    }

    function _convertHLPToUSDC(uint256 _amount, uint256 _hlpPrice) internal pure returns (uint256) {
        return _amount.mulDiv(_hlpPrice, 10 ** 24);
    }

    function _convertUSDCToHLP(uint256 _amount, uint256 _hlpPrice) internal pure returns (uint256) {
        return _amount.mulDiv(10 ** 24, _hlpPrice);
    }

    //a function that make sure the slippage is within the tolerance when buying/selling HLP
    function isWithinSlippage(uint256 _a, uint256 _b, uint256 _slippageBps) internal pure returns (bool) {
        uint256 _slippage = (_a * _slippageBps) / MAX_BPS;
        if (_a > _b) {
            return (_a - _b) <= _slippage;
        } else {
            return (_b - _a) <= _slippage;
        }
    }

    function _handlePODToken(address _user, uint256 position) internal {
        if (strategyAddresses.MasterChef != address(0)) {
            uint256 userBalance = balanceOf(_user);
            if (userBalance >= position) {
                _burn(_user, position);
            } else {
                _burn(_user, userBalance);
                uint256 remainingPosition = position - userBalance;
                IMasterChef(strategyAddresses.MasterChef).unstakeAndLiquidate(MCPID, _user, remainingPosition);
            }
        } else {
            _burn(_user, position);
        }
    }
    function withdrawArb(address _arb, address _to) external onlyKeeper {
        IERC20Upgradeable(_arb).safeTransfer(_to, IERC20Upgradeable(_arb).balanceOf(address(this)));
    }

    receive() external payable {}
}

