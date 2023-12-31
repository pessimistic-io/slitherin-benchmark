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

contract RumVault is IRumVault, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, ERC20BurnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;
    using MathUpgradeable for uint128;

    FeeConfiguration public feeConfiguration;
    StrategyAddresses public strategyAddresses;
    DebtAdjustmentValues public debtAdjustmentValues;

    address[] public allUsers;
    uint256[] public tokenIds;

    uint256 public MCPID;
    uint256 public MAX_BPS;
    uint256 public MAX_LEVERAGE;
    uint256 public MIN_LEVERAGE;
    uint256 public DTVLimit;
    uint256 public DTVSlippage;
    uint256 public timeAdjustment;

    uint256 public DENOMINATOR;
    uint256 public DECIMAL;
    address public keeper;

    mapping(address => PositionInfo[]) public positionInfo;
    mapping(address => bool) public allowedSenders;
    mapping(address => bool) public burner;
    mapping(address => bool) private isUser;
    mapping(uint256 => DepositRecord) public depositRecord;
    mapping(uint256 => WithdrawRecord) public withdrawRecord;
    mapping(address => mapping(uint256 => bool)) public inCloseProcess;
    mapping(address => uint256[]) public openOrderIds;
    mapping(address => uint256[]) public closeOrderIds;
    KeeperInfo public keeperInfo;
    uint256[50] private __gaps;

    modifier InvalidID(uint256 positionId, address user) {
        require(positionId < positionInfo[user].length, "RUM: positionID is not valid");
        _;
    }

    modifier zeroAddress(address addr) {
        require(addr != address(0), "Zero address");
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
        //@todo add require statement
        MAX_BPS = 10_000;
        MAX_LEVERAGE = 10_000;
        MIN_LEVERAGE = 3_000;
        DENOMINATOR = 1_000;
        DECIMAL = 1e18;
        feeConfiguration.fixedFeeSplit = 50;
        feeConfiguration.slippageTolerance = 500;
        debtAdjustmentValues.debtAdjustment = 1e18;
        debtAdjustmentValues.time = block.timestamp;

        __Ownable_init();
        __Pausable_init();
        __ERC20_init("RUM-POD", "RUM-POD");
    }

    /** ----------- Change onlyOwner functions ------------- */

    function setAllowed(address _sender, bool _allowed) public onlyOwner zeroAddress(_sender) {
        allowedSenders[_sender] = _allowed;
        emit SetAllowedSenders(_sender, _allowed);
    }

    function setBurner(address _burner, bool _allowed) public onlyOwner zeroAddress(_burner) {
        burner[_burner] = _allowed;
        emit SetBurner(_burner, _allowed);
    }

    function setMaxAndMinLeverage(uint256 _maxLeverage, uint256 _minLeverage) public onlyOwner {
        require(_maxLeverage >= _minLeverage, "Max leverage must be greater than min leverage");
        MAX_LEVERAGE = _maxLeverage;
        MIN_LEVERAGE = _minLeverage;
        emit UpdateMaxAndMinLeverage(_maxLeverage, _minLeverage);
    }

    function setProtocolFee(
        address _feeReceiver,
        uint256 _withdrawalFee,
        address _waterFeeReceiver,
        uint256 _liquidatorsRewardPercentage,
        uint256 _fixedFeeSplit,
        uint256 _hlpFee,
        uint256 _keeperFee
    ) external onlyOwner {
        feeConfiguration.feeReceiver = _feeReceiver;
        feeConfiguration.withdrawalFee = _withdrawalFee;
        feeConfiguration.waterFeeReceiver = _waterFeeReceiver;
        feeConfiguration.liquidatorsRewardPercentage = _liquidatorsRewardPercentage;
        feeConfiguration.fixedFeeSplit = _fixedFeeSplit;
        feeConfiguration.hlpFee = _hlpFee;
        keeperInfo.keeperFee = _keeperFee;

        emit ProtocolFeeChanged(_feeReceiver, _withdrawalFee, _waterFeeReceiver, _liquidatorsRewardPercentage, _fixedFeeSplit, _keeperFee);
    }

    function setStrategyAddresses(
        address _USDC,
        address _hmxCalculator,
        address _hlpLiquidityHandler,
        address _hlpStaking,
        address _hlpCompounder,
        address _water,
        address _MasterChef,
        address _WETH,
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
        strategyAddresses.WETH = _WETH;
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
            _WETH,
            _hlp,
            _hlpRewardHandler,
            _keeper
        );
    }

    function setDTVLimit(uint256 _DTVLimit, uint256 _DTVSlippage) public onlyOwner {
        require(_DTVSlippage <= 1000, "DTVSlippage must be less than 1000");
        DTVLimit = _DTVLimit;
        DTVSlippage = _DTVSlippage;
        emit DTVLimitSet(_DTVLimit, DTVSlippage);
    }

    //params Ratio: incrase % for each call of updateDebtAdjustment
    //timeAdjustment:
    function setDebtAdjustmentParams(uint256 _debtValueRatio, uint256 _timeAdjustment) external onlyOwner {
        require(_debtValueRatio <= 1e18, "Debt value ratio must be less than 1");
        debtAdjustmentValues.debtValueRatio = _debtValueRatio;
        timeAdjustment = _timeAdjustment;
    }

    function updateDebtAdjustment() external onlyOwner {
        // require(getUtilizationRate() > (DTVLimit), "Utilization rate is not greater than DTVLimit");
        // require(block.timestamp - debtAdjustmentValues.time > timeAdjustment, "Time difference is not greater than 72 hours");

        debtAdjustmentValues.debtAdjustment =
            debtAdjustmentValues.debtAdjustment +
            (debtAdjustmentValues.debtAdjustment * debtAdjustmentValues.debtValueRatio) /
            1e18;
        debtAdjustmentValues.time = block.timestamp;
    }

    //     function pause() external onlyOwner {
    //         _pause();
    //     }
    //
    //     function unpause() external onlyOwner {
    //         _unpause();
    //     }

    //@todo handle esToken
    //
    //     function transferEsGMX(address _destination) public onlyOwner {
    //         IRewardRouterV2(strategyAddresses.rewardVault).signalTransfer(_destination);
    //     }
    /** ----------- View functions ------------- */

    function getCurrentLeverageAmount(uint256 _positionID, address _user) public view returns (uint256) {
        PositionInfo memory _positionInfo = positionInfo[_user][_positionID];
        uint256 previousDA = _positionInfo.debtAdjustmentValue;
        uint256 userLeverageAmount = _positionInfo.leverageAmount;
        if (debtAdjustmentValues.debtAdjustment > previousDA) {
            userLeverageAmount = userLeverageAmount.mulDiv(debtAdjustmentValues.debtAdjustment, previousDA);
        }
        return (userLeverageAmount);
    }

    function getHLPPrice(bool _maximise) public view returns (uint256) {
        uint256 aum = ICalculator(strategyAddresses.hmxCalculator).getAUME30(_maximise);
        uint256 totalSupply = IERC20Upgradeable(strategyAddresses.hlp).totalSupply();

        return ICalculator(strategyAddresses.hmxCalculator).getHLPPrice(aum, totalSupply);
        //HLP Price in e12
    }

    //get this contract balance of hlp token(1e18)
    function getStakedHLPBalance() public view returns (uint256) {
        return IHLPStaking(strategyAddresses.hlpStaking).userTokenAmount(address(this));
    }

    function getAllUsers() external view returns (address[] memory) {
        return allUsers;
    }

    function getNumbersOfPosition(address _user) external view returns (uint256) {
        return positionInfo[_user].length;
    }

    function getUtilizationRate() external view returns (uint256) {
        uint256 totalWaterDebt = IWater(strategyAddresses.water).totalDebt();
        uint256 totalWaterAssets = IWater(strategyAddresses.water).balanceOfUSDC();
        return totalWaterDebt == 0 ? 0 : totalWaterDebt.mulDiv(DECIMAL, totalWaterAssets + totalWaterDebt);
    }

    function getAggregatePosition(address _user) external view returns (uint256) {
        uint256 aggregatePosition;
        for (uint256 i = 0; i < positionInfo[_user].length; i++) {
            PositionInfo memory _userInfo = positionInfo[_user][i];
            if (!_userInfo.isLiquidated && !_userInfo.isClosed) {
                aggregatePosition += positionInfo[_user][i].position;
            }
        }
        return aggregatePosition;
    }

    function getPosition(uint256 _positionID, address _user) public view returns (uint256, uint256, uint256, uint256, uint256) {
        PositionInfo memory _positionInfo = positionInfo[_user][_positionID];
        if (_positionInfo.isClosed || _positionInfo.isLiquidated) return (0, 0, 0, 0, 0);

        uint256 currentPositionValue = _convertHLPToUSDC(_positionInfo.position, getHLPPrice(true));

        uint256 OriginalLeverageAmount = _positionInfo.leverageAmount;

        uint256 currentDTV = OriginalLeverageAmount.mulDiv(DECIMAL, currentPositionValue);

        uint256 leveageAmountWithDA = getCurrentLeverageAmount(_positionID, _user);

        uint256 currentDTVWithDA = leveageAmountWithDA.mulDiv(DECIMAL, currentPositionValue);

        return (currentDTV, OriginalLeverageAmount, currentPositionValue, currentDTVWithDA, leveageAmountWithDA);
    }

    /** ----------- User functions ------------- */
    //@todo add logic to handle rewards from HMX
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
        require(_leverage >= MIN_LEVERAGE && _leverage <= MAX_LEVERAGE, "RUM: Invalid leverage");
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
        //emit an event called
    }

    //@dev backend listen to the event of LogRefund and call this function
    function fulfillOpenCancellation(uint256 orderId) public onlyKeeper returns (bool) {
        DepositRecord storage dr = depositRecord[orderId];
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

        (, , , uint256 currentDTVWithDA, ) = getPosition(_positionID, msg.sender);

        if (currentDTVWithDA >= (DTVLimit * DTVSlippage) / 1000) {
            revert("Wait for liquidation");
        }

        // _positionInfo.leverageAmount = LeverageAmountWihtDA;
        //unstake, approve, create withdraw order
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

        uint256 reDepositAmount = _positionInfo.position;
        //redeposit the position to hlp staking
        IERC20Upgradeable(strategyAddresses.hlp).approve(strategyAddresses.hlpStaking, reDepositAmount);
        IHLPStaking(strategyAddresses.hlpStaking).deposit(address(this), reDepositAmount);

        inCloseProcess[wr.user][wr.positionID] = false;
        wr.isOrderCompleted = true;

        emit ClosePositionCancelled(wr.user, _positionInfo.position, block.timestamp, orderId, wr.positionID);

        return true;
        //@add an item in the WithdrawtRecord to show that the event is cancelled.
    }

    function fulfillClosePosition(uint256 _orderId, uint256 _returnedUSDC) public onlyKeeper returns (bool) {
        WithdrawRecord storage wr = withdrawRecord[_orderId];
        PositionInfo storage _positionInfo = positionInfo[wr.user][wr.positionID];

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

        _burn(wr.user, _positionInfo.position);

        (, , , , uint256 leverageAmountWihtDA) = getPosition(wr.positionID, wr.user);

        wr.fullDebtValue = leverageAmountWihtDA;
        wr.returnedUSDC = _returnedUSDC;

        extraData.positionPreviousValue = _convertHLPToUSDC(_positionInfo.position, _positionInfo.buyInPrice);
        extraData.returnedValue = _returnedUSDC;
        extraData.orderId = _orderId;

        if (_returnedUSDC > extraData.positionPreviousValue) {
            extraData.profits = _returnedUSDC - extraData.positionPreviousValue;
        }

        uint256 waterRepayment;
        (uint256 waterProfits, uint256 leverageUserProfits) = _getProfitSplit(extraData.profits, _positionInfo.leverageMultiplier);

        if (extraData.returnedValue < (wr.fullDebtValue + waterProfits)) {
            _positionInfo.liquidator = msg.sender;
            _positionInfo.isLiquidated = true;
            waterRepayment = extraData.returnedValue;
        } else {
            extraData.toLeverageUser = (extraData.returnedValue - wr.fullDebtValue - extraData.profits) + leverageUserProfits;
            waterRepayment = extraData.returnedValue - extraData.toLeverageUser - waterProfits;

            _positionInfo.isClosed = true;
            _positionInfo.position = 0;
            _positionInfo.leverageAmount = 0;
        }

        if (waterProfits > 0) {
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(feeConfiguration.waterFeeReceiver, waterProfits);
        }

        IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.water, wr.fullDebtValue);
        IWater(strategyAddresses.water).repayDebt(wr.fullDebtValue, waterRepayment);

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

        (, , , uint256 currentDTVWithDA, ) = getPosition(_positionID, _user);

        require(currentDTVWithDA >= (DTVLimit * DTVSlippage) / 1000, "Liquidation threshold not reached yet");

        // _positionInfo.leverageAmount = LeverageAmountWihtDA;

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

        // (uint256 DebtToValueRatio, , , ) = getPosition(wr.positionID, wr.user);
        // require(DebtToValueRatio >= (DTVLimit * DTVSlippage) / 1000, "Liquidation Threshold Has Not Reached");

        IHlpRewardHandler(strategyAddresses.hlpRewardHandler).claimUSDCRewards(wr.user);

        (, , , , uint256 leverageAmountWihtDA) = getPosition(wr.positionID, wr.user);

        uint256 position = _positionInfo.position;
        wr.returnedUSDC = _returnedUSDC;

        uint256 userAmountStaked;
        if (strategyAddresses.MasterChef != address(0)) {
            (userAmountStaked, ) = IMasterChef(strategyAddresses.MasterChef).userInfo(MCPID, wr.user);
            if (userAmountStaked > 0) {
                uint256 amountToBurnFromUser;
                if (userAmountStaked > position) {
                    amountToBurnFromUser = position;
                } else {
                    amountToBurnFromUser = userAmountStaked;
                    uint256 _position = position - userAmountStaked;
                    _burn(wr.user, _position);
                }
                IMasterChef(strategyAddresses.MasterChef).unstakeAndLiquidate(MCPID, wr.user, amountToBurnFromUser);
            }
        } else {
            _burn(wr.user, position);
        }

        uint256 liquidatorReward;
        if (wr.returnedUSDC >= leverageAmountWihtDA) {
            wr.returnedUSDC -= leverageAmountWihtDA;

            liquidatorReward = wr.returnedUSDC.mulDiv(feeConfiguration.liquidatorsRewardPercentage, MAX_BPS);
            IERC20Upgradeable(strategyAddresses.USDC).safeTransfer(wr.liquidator, liquidatorReward);

            uint256 leftovers = wr.returnedUSDC - liquidatorReward;

            IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.water, leftovers + leverageAmountWihtDA);
            IWater(strategyAddresses.water).repayDebt(leverageAmountWihtDA, leftovers + leverageAmountWihtDA);
        } else {
            IERC20Upgradeable(strategyAddresses.USDC).safeIncreaseAllowance(strategyAddresses.water, wr.returnedUSDC);
            IWater(strategyAddresses.water).repayDebt(leverageAmountWihtDA, wr.returnedUSDC);
        }

        uint256 outputAmount = 0;

        _positionInfo.liquidator = msg.sender;
        _positionInfo.isLiquidated = true;
        _positionInfo.position = 0;

        IHlpRewardHandler(strategyAddresses.hlpRewardHandler).setDebtRecordUSDC(wr.user);

        emit Liquidated(wr.user, wr.positionID, msg.sender, outputAmount, liquidatorReward);
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
    function _getProfitSplit(uint256 _profit, uint256 _leverage) internal view returns (uint256, uint256) {
        if (_profit == 0) {
            return (0, 0);
        }
        uint256 split = (feeConfiguration.fixedFeeSplit * _leverage + (feeConfiguration.fixedFeeSplit * MAX_BPS)) / 100;
        uint256 toWater = (_profit * split) / MAX_BPS;
        uint256 toRumUser = _profit - toWater;
        return (toWater, toRumUser);
    }

    function _convertHLPToUSDC(uint256 _amount, uint256 _hlpPrice) internal pure returns (uint256) {
        return _amount.mulDiv(_hlpPrice, 10 ** 24);
    }

    function _convertUSDCToHLP(uint256 _amount, uint256 _hlpPrice) internal pure returns (uint256) {
        return _amount.mulDiv(10 ** 24, _hlpPrice);
    }

    function takeAll(address _inputSsset, uint256 _amount) public onlyOwner {
        IERC20Upgradeable(_inputSsset).transfer(msg.sender, _amount);
    }

    //
    //function for owner to transfer all eth in the contract out
    function takeAllETH() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    //deposit HLP token
    // function depositHLP() external onlyOwner {
    //     //check contract hlp balance
    //     uint256 balanceOfHLP = IERC20Upgradeable(strategyAddresses.hlp).balanceOf(address(this));
    //     //approve hlp staking contract
    //     IERC20Upgradeable(strategyAddresses.hlp).approve(strategyAddresses.hlpStaking, balanceOfHLP);
    //     IHLPStaking(strategyAddresses.hlpStaking).deposit(address(this), balanceOfHLP);
    // }

    function isWithinSlippage(uint256 _a, uint256 _b, uint256 _slippageBps) public view returns (bool) {
        uint256 _slippage = (_a * _slippageBps) / MAX_BPS;
        if (_a > _b) {
            return (_a - _b) <= _slippage;
        } else {
            return (_b - _a) <= _slippage;
        }
    }

    //add a function to set keeper
    function setKeeperInfo(address _keeper, uint256 _keeperFee) external onlyOwner {
        keeperInfo.keeper = _keeper;
        keeper = _keeper;
        keeperInfo.keeperFee = _keeperFee;
    }

    //approve USDC to water
    function approveUSDC() external onlyOwner {
        IERC20Upgradeable(strategyAddresses.USDC).approve(strategyAddresses.water, type(uint256).max);
    }

    receive() external payable {}
}

