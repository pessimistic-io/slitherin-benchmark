//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IStfxStorage} from "./IStfxStorage.sol";

interface IStfxVault is IStfxStorage {
    event InitializedVault(
        address _reader,
        address _stfxImplementation,
        uint256 _capacityPerStf,
        uint256 _minInvestmentAmount,
        uint256 _maxInvestmentAmount,
        uint256 _maxLeverage,
        address _usdc,
        address _weth,
        address _admin,
        address _treasury
    );
    event NewFundCreated(
        address indexed baseToken,
        uint256 fundraisingPeriod,
        uint256 entryPrice,
        uint256 targetPrice,
        uint256 liquidationPrice,
        uint256 leverage,
        bool tradeDirection,
        address indexed stfxAddress,
        address indexed manager
    );
    event DepositIntoFund(address indexed _stfxAddress, address indexed investor, uint256 amount);
    event FundraisingClosed(address indexed _stfxAddress);
    event FundraisingCloseAndVaultOpened(address indexed _stfxAddress, bool _isLimit, uint256 triggerPrice);
    event VaultOpened(address indexed _stfAddress, bool isLimit, uint256 triggerPrice);
    event VaultClosed(
        address indexed _stfAddress, uint256 size, bool isLimit, uint256 triggerPrice, bool closedCompletely
    );
    event OrderUpdated(
        address indexed _stfxAddress, uint256 _size, uint256 _triggerPrice, bool _isOpen, bool _triggerAboveThreshold
    );
    event OrderCancelled(address indexed _stfxAddress, uint256 _orderIndex, bool _isOpen, uint256 _totalRaised);
    event CreatedPositionAgain(address indexed _stfxAddress, bool _isOpen, uint256 _triggerPrice);
    event FeesTransferred(
        address indexed _stfxAddress, uint256 _remainingBalance, uint256 _managerFee, uint256 _protocolFee
    );
    event Claimed(address indexed investor, address indexed stfxAddress, uint256 amount);
    event VaultLiquidated(address indexed stfxAddress);
    event NoFillVaultClosed(address indexed stfxAddress);
    event CapacityPerStfChanged(uint256 capacity);
    event MaxInvestmentAmountChanged(uint256 maxAmount);
    event MinInvestmentAmountChanged(uint256 maxAmount);
    event MaxLeverageChanged(uint256 maxLeverage);
    event MinLeverageChanged(uint256 minLeverage);
    event MaxFundraisingPeriodChanged(uint256 maxFundraisingPeriod);
    event ManagerFeeChanged(uint256 managerFee);
    event ProtocolFeeChanged(uint256 protocolFee);
    event OwnerChanged(address indexed newOwner);
    event StfxImplementationChanged(address indexed stfx);
    event ReaderAddressChanged(address indexed reader);
    event FundDeadlineChanged(address indexed stfxAddress, uint256 fundDeadline);
    event MaxDeadlineForPositionChanged(uint256 maxDeadlineForPosition);
    event UsdcAddressChanged(address indexed usdc);
    event WethAddressChanged(address indexed weth);
    event AdminChanged(address indexed admin);
    event TreasuryChanged(address indexed treasury);
    event ReferralCodeChanged(bytes32 referralCode);
    event WithdrawEth(address indexed receiver, uint256 amount);
    event WithdrawToken(address indexed token, address indexed receiver, uint256 amount);
    event WithdrawFromStf(
        address indexed stfxAddress, address indexed receiver, bool isEth, address indexed token, uint256 amount
    );
    event StfStatusUpdate(address indexed stfxAddress, StfStatus status);
    event StfTotalRaisedUpdate(address indexed stfxAddress, uint256 totalRaised);
    event StfRemainingBalanceUpdate(address indexed stfxAddress, uint256 remainingBalance);
    event ManagingFundUpdate(address indexed manager, bool isManaging);

    function getUserAmount(address _stfxAddress, address _investor) external view returns (uint256);

    function getClaimAmount(address _stfxAddress, address _investor) external view returns (uint256);

    function getClaimed(address _stfxAddress, address _investor) external view returns (bool);

    function getPosition(address _stfxAddress)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, bool);

    function shouldDistribute(address _stfxAddress) external view returns (bool);

    function isDistributed(address _stfxAddress) external view returns (bool);

    function isClosed(address _stfxAddress) external view returns (bool);

    function isOpened(address _stfxAddress) external view returns (bool);

    function createNewStf(Stf calldata _fund) external returns (address);

    function depositIntoFund(address _stfxAddress, uint256 amount) external;

    function closeFundraising(address _stfxAddress) external;

    function closeFundraisingAndOpenPosition(address _stfxAddress, bool _isLimit, uint256 _triggerPrice)
        external
        payable;

    function openPosition(address _stfxAddress, bool _isLimit, uint256 _triggerPrice) external payable;

    function closePosition(
        address _stfxAddress,
        bool _isLimit,
        uint256 _size,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external payable;

    function distributeProfits(address _stfxAddress) external;

    function cancelOrder(address _stfxAddress, uint256 _orderIndex, bool _isOpen) external;

    function createPositionAgain(
        address _stfxAddress,
        bool _isLimit,
        bool _isOpen,
        uint256 _size,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external payable;

    function claimableAmount(address _stfxAddress, address _investor) external view returns (uint256);

    function claim(address _stfxAddress) external;

    function closeLiquidatedVault(address _stfxAddress) external;

    function cancelVault(address _stfxAddress) external;

    function cancelStfByManager(address _stfxAddress) external;

    function cancelStfAfterOpening(address _stfxAddress, uint256 _orderIndex) external;

    function cancelStfAfterPositionDeadline(
        address _stfxAddress, 
        bool hasCloseOrder,
        uint256 _orderIndex,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external payable;

    function setCapacityPerStf(uint256 _capacity) external;

    function setMinInvestmentAmount(uint256 _amount) external;

    function setMaxInvestmentAmount(uint256 _amount) external;

    function setMaxLeverage(uint256 _maxLeverage) external;

    function setMinLeverage(uint256 _minLeverage) external;

    // function setNewManager(address _stfxAddress, address _manager) external;

    function setManagerFee(uint256 _managerFee) external;

    function setProtocolFee(uint256 _protocolFee) external;

    function setOwner(address _owner) external;

    function setStfxImplementation(address _stfx) external;

    function setReader(address _reader) external;

    function setFundDeadline(address _stfx, uint256 _fundDeadline) external;

    function setStfStatus(StfStatus) external;

    function setStfTotalRaised(uint256 totalRaised) external;

    function setStfRemainingBalance(uint256 remainingBalance) external;

    function setIsManagingFund(address _manager, bool _isManaging) external;

    function withdrawEth(address receiver, uint256 amount) external;

    function withdrawToken(address token, address receiver, uint256 amount) external;

    function withdrawFromStf(address _stfxAddress, address receiver, bool isEth, address token, uint256 amount) external;
}

