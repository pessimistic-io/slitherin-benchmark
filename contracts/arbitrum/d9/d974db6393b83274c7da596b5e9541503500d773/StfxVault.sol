// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {IERC20} from "./IERC20.sol";
import {IStfx} from "./IStfx.sol";
import {IStfxPerp} from "./IStfxPerp.sol";
import {IStfxGmx} from "./IStfxGmx.sol";
import {IGmxVault} from "./IGmxVault.sol";
import {IStfxVault} from "./IStfxVault.sol";
import {Clones} from "./Clones.sol";
import {Pausable} from "./Pausable.sol";
import {IReader} from "./IReader.sol";

error ZeroAddress();
error ZeroAmount();
error ZeroTokenBalance();
error NoAccess(address desired, address given);
error StillFundraising(uint256 desired, uint256 given);
error InvalidChainId(uint256 desired, uint256 given);
error BelowMin(uint256 min, uint256 given);
error AboveMax(uint256 max, uint256 given);

error FundExists(address fund);
error NoBaseToken(address token);
/// Direction: 0 = long, 1 = short.
error NotEligible(uint256 entry, uint256 exit, bool direction);
error AlreadyOpened();
error MismatchStatus(IStfxVault.StfStatus given);
error CantOpen();
error CantClose();
error NotOpened();
error NotFinalised();
error NoCloseActions();
error OpenPosition();
error NoOpenPositions();

/// @title StfxVault
/// @author 7811, abhi3700
/// @notice Contract for the investors to deposit and for managers to open and close positions
contract StfxVault is IStfxVault, Pausable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // usdc address
    address private USDC;
    // weth address
    address private WETH;

    // owner/deployer of the contract
    // used for setting and updating the logic changes
    address public owner;
    // address used by the backend bot to close/cancel the stfs
    address public admin;
    // address used to collect the protocol fees
    address public treasury;
    // implementation of the `Stfx` contract
    address public stfxImplementation;

    IReader public reader;

    // max amount which can be fundraised by the manager per stf
    uint256 public capacityPerStf;
    // min investment amount per investor per stf
    uint256 public minInvestmentAmount;
    // max investment amount per investor per stf
    uint256 public maxInvestmentAmount;
    // percentage of fees from the profits of the stf to the manager (default - 15e18 (15%))
    uint256 public managerFee;
    // percentage of fees from the profits of the stf to the protocol (default - 5e18 (5%))
    uint256 public protocolFee;
    // max leverage which can be used by the manager when creating an stf
    uint256 public maxLeverage;
    // min leverage which can be used by the manager when creating an stf
    uint256 public minLeverage;
    // max fundraising period which can be used by the manager to raise funds (defaults - 1 week)
    uint256 public maxFundraisingPeriod;
    // the max time a trade can be open, default - 30 days
    uint256 public maxDeadlineForPosition;
    // referralCode used for opening a position on the dex
    bytes32 public referralCode;

    mapping(address => StfInfo) public stfInfo;
    // manager's address to indicate if the manager is managing a fund currently
    // manager can only manage one stf per address
    mapping(address => bool) public isManagingFund;
    // stf address to the actual amount raised before swaps for cancel order
    // will be used to calculate `utilizationRatio` when using partial amount for opening a position
    mapping(address => uint256) public actualTotalRaised;
    // mapping of stf and the manager fees
    mapping(address => uint256) public managerFees;
    // mapping of stf and the protocol fees 
    mapping(address => uint256) public protocolFees;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZE
    //////////////////////////////////////////////////////////////*/

    /// @notice initializing state variables in the contructor
    /// @dev require checks to make sure the addresses are not zero addresses
    /// @param _reader `Reader` contract address
    /// @param _stfxImplementation `Stfx` contract address
    /// @param _capacityPerStf max amount which can be fundraised by the manager per stf
    /// @param _minInvestmentAmount min investment amount per investor per stf
    /// @param _maxInvestmentAmount max investment amount per investor per stf
    /// @param _maxLeverage max leverage which can be used by the manager when creating an stf
    /// @param _usdc USDC contract address
    /// @param _weth WETH contract address
    /// @param _admin address used by the bot to close/cancel Stfs
    /// @param _treasury address used to collect protocol fees
    constructor(
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
    ) {
        if (_reader == address(0)) revert ZeroAddress();
        if (_stfxImplementation == address(0)) revert ZeroAddress();
        if (_usdc == address(0)) revert ZeroAddress();
        if (_weth == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();
        reader = IReader(_reader);
        owner = msg.sender;
        stfxImplementation = _stfxImplementation;
        capacityPerStf = _capacityPerStf;
        minInvestmentAmount = _minInvestmentAmount;
        maxInvestmentAmount = _maxInvestmentAmount;
        minLeverage = 1e6;
        maxLeverage = _maxLeverage;
        USDC = _usdc;
        WETH = _weth;
        managerFee = 15e18;
        protocolFee = 5e18;
        maxFundraisingPeriod = 1 weeks;
        admin = _admin;
        treasury = _treasury;
        maxDeadlineForPosition = 2592000; // 30 days

        emit InitializedVault(
            _reader,
            _stfxImplementation,
            _capacityPerStf,
            _minInvestmentAmount,
            _maxInvestmentAmount,
            _maxLeverage,
            _usdc,
            _weth,
            _admin,
            _treasury
            );
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice modifier for the setters to be called only by the manager
    modifier onlyOwner() {
        if (msg.sender != owner) revert NoAccess(owner, msg.sender);
        _;
    }

    /// @notice modifier for cancel vaults to be called only by the admin
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NoAccess(admin, msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW
    //////////////////////////////////////////////////////////////*/

    // TODO (should we move view functions to Reader?)
    function getUserAmount(address _stfxAddress, address _investor) external view override returns (uint256) {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        return _stf.userAmount[_investor];
    }

    function getClaimAmount(address _stfxAddress, address _investor) external view override returns (uint256) {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        return _stf.claimAmount[_investor];
    }

    function getClaimed(address _stfxAddress, address _investor) external view override returns (bool) {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        return _stf.claimed[_investor];
    }

    function getStfInfo(address _stfxAddress)
        external
        view
        returns (address, address, uint256, uint256, uint256, uint256, StfStatus)
    {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        return (
            _stf.stfxAddress,
            _stf.manager,
            _stf.totalRaised,
            _stf.remainingAmountAfterClose,
            _stf.endTime,
            _stf.fundDeadline,
            _stf.status
        );
    }

    function getPosition(address _stfxAddress)
        public
        view
        returns (
            uint256 size,
            uint256 collateral,
            uint256 price,
            uint256 entryFundingRate,
            uint256 reserveAmount,
            uint256 realisedPnl,
            bool isProfit
        )
    {
        Stf memory _stf = IStfxGmx(_stfxAddress).getStf();
        address _dex = reader.getDex()[0];

        {
            (size, collateral, price, entryFundingRate, reserveAmount, realisedPnl, isProfit,) = IGmxVault(_dex)
                .getPosition(_stfxAddress, _stf.tradeDirection ? _stf.baseToken : USDC, _stf.baseToken, _stf.tradeDirection);
        }
    }

    function shouldDistribute(address _stfxAddress) external view returns (bool) {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        (uint256 _size,,,,,,) = getPosition(_stfxAddress);
        if (_stf.status == StfStatus.CLOSED && _size == 0) {
            return true;
        }
        return false;
    }

    function shouldCancelOpenLimitOrder(address _stfxAddress) public view returns (bool) {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        (uint256 _size,,,,,,) = getPosition(_stfxAddress);
        if (_stf.status == StfStatus.OPENED && _size == 0 && block.timestamp > _stf.endTime + _stf.fundDeadline) {
            return true;
        }
        return false;
    }

    function isDistributed(address _stfxAddress) external view returns (bool) {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if(_stf.status == StfStatus.DISTRIBUTED) return true;
    }

    function isClosed(address _stfxAddress) external view returns (bool) {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if(_stf.status == StfStatus.CLOSED) return true;
    }

    function isOpened(address _stfxAddress) external view returns (bool) {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if(_stf.status == StfStatus.OPENED) return true;
    }

    function isCancelled(address _stfxAddress) external view returns (bool) {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if(_stf.status == StfStatus.CANCELLED) return true;
    }

    function isNotOpened(address _stfxAddress) external view returns (bool) {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if(_stf.status == StfStatus.NOT_OPENED) return true;
    }

    function isLiquidated(address _stfxAddress) external view returns (bool) {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if(_stf.status == StfStatus.LIQUIDATED) return true;
    }

    function getStatusOfStf(address _stfxAddress) external view returns (StfStatus) {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        return _stf.status;
    }

    function getPnl(address _stfxAddress) 
        external 
        view 
        returns (
            uint256 mFee, 
            uint256 pFee, 
            int256 pnlBeforeFees,
            int256 pnlAfterFees, 
            bool isDistributed
        ) 
    {   
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if (_stf.status == StfStatus.DISTRIBUTED) isDistributed = true;
        mFee = managerFees[_stfxAddress];
        pFee = protocolFees[_stfxAddress];
        pnlBeforeFees = int256(_stf.remainingAmountAfterClose + mFee + pFee) - int256(actualTotalRaised[_stfxAddress]);
        pnlAfterFees = int256(_stf.remainingAmountAfterClose) - int256(actualTotalRaised[_stfxAddress]);
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a new Single Trade Fund (STF)
    /// @dev returns the address of the proxy contract with Stfx.sol implementation
    /// @param _stf the fund details, check `IStfxStorage.Stf`
    /// @return stfxAddress address of the proxy contract which is deployed
    function createNewStf(Stf calldata _stf) external override whenNotPaused returns (address stfxAddress) {
        if (isManagingFund[msg.sender]) revert FundExists(msg.sender);
        if (_stf.fundraisingPeriod < 15 minutes) revert BelowMin(15 minutes, _stf.fundraisingPeriod);
        if (_stf.fundraisingPeriod > maxFundraisingPeriod) {
            revert AboveMax(maxFundraisingPeriod, _stf.fundraisingPeriod);
        }
        if (_stf.leverage < minLeverage) revert BelowMin(minLeverage, _stf.leverage);
        if (_stf.leverage > maxLeverage) revert AboveMax(maxLeverage, _stf.leverage);
        // checks the dex if the token is eligible for opening a position
        if (!reader.getBaseTokenEligible(_stf.baseToken)) revert NoBaseToken(_stf.baseToken);
        // checks if the entry and the target price are eligible (0.1x - 10x of the currentPrice)
        if (!reader.checkPrices(_stf.entryPrice, _stf.targetPrice, _stf.baseToken, _stf.tradeDirection)) {
            revert NotEligible(_stf.entryPrice, _stf.targetPrice, _stf.tradeDirection);
        }

        stfxAddress = Clones.clone(stfxImplementation);
        IStfx(stfxAddress).initialize(_stf, msg.sender, USDC, WETH, address(reader));

        stfInfo[stfxAddress].stfxAddress = stfxAddress;
        stfInfo[stfxAddress].manager = msg.sender;
        stfInfo[stfxAddress].endTime = block.timestamp + _stf.fundraisingPeriod;
        stfInfo[stfxAddress].fundDeadline = 72 hours;
        isManagingFund[msg.sender] = true;

        emit NewFundCreated(
            _stf.baseToken,
            _stf.fundraisingPeriod,
            _stf.entryPrice,
            _stf.targetPrice,
            _stf.liquidationPrice,
            _stf.leverage,
            _stf.tradeDirection,
            stfxAddress,
            msg.sender
            );
    }

    /// @notice deposit a particular amount into an stf for the manager to open a position
    /// @dev `fundraisingPeriod` has to end and the `totalRaised` should not be more than `maxInvestmentPerStf`
    /// @dev amount has to be between `minInvestmentAmount` and `maxInvestmentAmount`
    /// @dev approve has to be called before this method for the investor to transfer usdc to this contract
    /// @param _stfxAddress address of the stf the investor wants to invest
    /// @param amount amount the investor wants to deposit
    function depositIntoFund(address _stfxAddress, uint256 amount) external override whenNotPaused {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if (block.timestamp > _stf.endTime) revert AboveMax(_stf.endTime, block.timestamp);
        if (amount < minInvestmentAmount) revert BelowMin(minInvestmentAmount, amount);
        if (_stf.userAmount[msg.sender] + amount > maxInvestmentAmount) {
            revert AboveMax(maxInvestmentAmount, _stf.userAmount[msg.sender] + amount);
        }
        if (_stf.status != StfStatus.NOT_OPENED) revert AlreadyOpened();
        if (_stf.totalRaised + amount > capacityPerStf) revert AboveMax(capacityPerStf, _stf.totalRaised + amount);

        _stf.totalRaised += amount;
        _stf.userAmount[msg.sender] += amount;
        actualTotalRaised[_stfxAddress] += amount;

        IERC20(USDC).transferFrom(msg.sender, address(this), amount);
        emit DepositIntoFund(_stfxAddress, msg.sender, amount);
    }

    /// @notice allows the manager to close the fundraising and open a position later
    /// @dev changes the `_stf.endTime` to the current `block.timestamp`
    /// @param _stfxAddress address of the stf where the manager wants to close fundraising
    function closeFundraising(address _stfxAddress) external override whenNotPaused {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if (_stf.manager != msg.sender) revert NoAccess(_stf.manager, msg.sender);
        if (_stf.status != StfStatus.NOT_OPENED) revert AlreadyOpened();
        if (_stf.totalRaised < 1) revert ZeroAmount();
        if (block.timestamp >= _stf.endTime) revert CantClose();

        _stf.endTime = block.timestamp;

        emit FundraisingClosed(_stfxAddress);
    } 

    /// @notice allows the manager to end the `fundraisingPeriod` early and open a market position
    /// @dev transfers the `totalRaised` usdc of the `stfxAddress` to the `Stfx` contract
    /// @param _stfxAddress address of the stf the manager wants to open a market position early
    /// @param _isLimit if true, then its a limit order, else a market order
    /// @param _triggerPrice price input depending on the latest price from the dex
    function closeFundraisingAndOpenPosition(address _stfxAddress, bool _isLimit, uint256 _triggerPrice)
        external
        payable
        override
        whenNotPaused
    {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if (_stf.manager != msg.sender) revert NoAccess(_stf.manager, msg.sender);
        if (_stf.status != StfStatus.NOT_OPENED) revert AlreadyOpened();
        if (block.timestamp >= _stf.endTime) revert CantClose();
        if (_stf.totalRaised < 1) revert ZeroAmount();

        // update state variables
        _stf.status = StfStatus.OPENED;
        _stf.endTime = block.timestamp;

        // transfer first and then call `openPosition()`
        IERC20(USDC).transfer(_stfxAddress, _stf.totalRaised);

        if (block.chainid == 42161) {
            IStfxGmx(_stfxAddress).openPosition{value: msg.value}(_isLimit, _triggerPrice, _stf.totalRaised);
        } else if (block.chainid == 10) {
            if (!IStfxPerp(_stfxAddress).openPosition()) revert CantOpen();
        }

        emit FundraisingCloseAndVaultOpened(_stfxAddress, _isLimit, _triggerPrice);
    }

    /// @notice allows the manager to open a limit or a market order
    /// @dev can be called only after the `fundraisingPeriod` is over
    /// @param _stfxAddress address of the stf. the manager wants to open an order
    /// @param _isLimit if true, then its a limit order, else a market order
    /// @param _triggerPrice price input depending on the latest price from the dex and whether its a limit or a market order
    function openPosition(address _stfxAddress, bool _isLimit, uint256 _triggerPrice)
        external
        payable
        override
        whenNotPaused
    {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if (msg.sender != _stf.manager) revert NoAccess(_stf.manager, msg.sender);
        if (_stf.endTime > block.timestamp) revert StillFundraising(_stf.endTime, block.timestamp);
        if (_stf.status != StfStatus.NOT_OPENED) revert AlreadyOpened();
        if (_stf.totalRaised < 1) revert ZeroAmount();

        _stf.status = StfStatus.OPENED;

        // transfer first and then call `openPosition()`
        IERC20(USDC).transfer(_stfxAddress, _stf.totalRaised);

        if (block.chainid == 42161) {
            IStfxGmx(_stfxAddress).openPosition{value: msg.value}(_isLimit, _triggerPrice, _stf.totalRaised);
        } else if (block.chainid == 10) {
            if (!IStfxPerp(_stfxAddress).openPosition()) revert CantOpen();
        }

        emit VaultOpened(_stfxAddress, _isLimit, _triggerPrice);
    }

    /// @notice allows the manager to close a limit or a market order
    /// @dev can be called only if theres a position already open
    /// @dev `stf.status` will be `CLOSED` and `isManagingFund(manager)` will be `false` only when the entire position size is closed
    /// @param _stfxAddress address of the stf, the manager wants to close the existing position
    /// @param _isLimit if true, then its a limit order, else a market order
    /// @param _size the position size which the manager wants to close
    /// @param _triggerPrice price input depending on the latest price from the dex and whether its a limit or a market order
    /// @param _triggerAboveThreshold bool to check if the `triggerPrice` is above or below the `currentPrice`, used for SL/TP
    function closePosition(
        address _stfxAddress,
        bool _isLimit,
        uint256 _size,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external payable override whenNotPaused {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        (uint256 size,,,,,,) = getPosition(_stfxAddress);
        if (msg.sender != _stf.manager && msg.sender != admin) revert NoAccess(_stf.manager, msg.sender);
        if (_stf.status != StfStatus.OPENED) revert NoOpenPositions();
        if (_size != size) revert CantClose();

        bool closed;
        if (block.chainid == 42161) {
            closed = IStfxGmx(_stfxAddress).closePosition{value: msg.value}(
                _isLimit, _size, _triggerPrice, _triggerAboveThreshold
            );
        } else if (block.chainid == 10) {
            if (!IStfxPerp(_stfxAddress).closePosition()) revert CantClose();
        }

        if (closed) {
            _stf.status = StfStatus.CLOSED;
        }

        emit VaultClosed(_stfxAddress, _size, _isLimit, _triggerPrice, closed);
    }

    /// @notice allows the manager to cancel an order
    /// @dev checks if an order exists, will revert from the dex if an order has already been executed
    /// @param _stfxAddress address of the stf, the manager wants to cancel the existing order
    /// @param _orderIndex the order index from the dex
    /// @param _isOpen if true, the manager can cancel an open order, else, the manager can cancel a close order
    function cancelOrder(address _stfxAddress, uint256 _orderIndex, bool _isOpen) external override whenNotPaused {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if (msg.sender != _stf.manager && msg.sender != admin) revert NoAccess(_stf.manager, msg.sender);

        if (_isOpen) {
            if (_stf.status != StfStatus.OPENED) revert AlreadyOpened();
            _stf.status = StfStatus.NOT_OPENED;
            uint256 remainingBalance = IStfxGmx(_stfxAddress).cancelOrder(_orderIndex, _isOpen);
            _stf.totalRaised = remainingBalance;
        } else {
            if (_stf.status != StfStatus.OPENED && _stf.status != StfStatus.CLOSED) revert NoCloseActions();
            _stf.status = StfStatus.OPENED;
            isManagingFund[_stf.manager] = true;
            IStfxGmx(_stfxAddress).cancelOrder(_orderIndex, _isOpen);
        }

        emit OrderCancelled(_stfxAddress, _orderIndex, _isOpen, _stf.totalRaised);
    }

    /// @notice allows the manager create a position again in case the position does not get executed by the dex
    /// @dev `stf.status` will be `CLOSED` and `isManagingFund(manager)` will be `false` only when the entire position size is closed
    /// @param _stfxAddress address of the stf, the manager wants to create a position again
    /// @param _isLimit if true, then its a limit order, else a market order
    /// @param _isOpen if true, the manager can create an open position, else, the manager can create a close position
    /// @param _size the position size which the manager wants to close
    /// @param _triggerPrice price input depending on the latest price from the dex and whether its a limit or a market order
    /// @param _triggerAboveThreshold bool to check if the `triggerPrice` is above or below the `currentPrice`, used for SL/TP
    function createPositionAgain(
        address _stfxAddress,
        bool _isLimit,
        bool _isOpen,
        uint256 _size,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external payable override whenNotPaused {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if (msg.sender != _stf.manager) revert NoAccess(_stf.manager, msg.sender);

        if (_isOpen) {
            if (_stf.status != StfStatus.OPENED) revert AlreadyOpened();
            if (IERC20(USDC).balanceOf(_stfxAddress) < 1) revert ZeroTokenBalance();
            IStfxGmx(_stfxAddress).openPosition{value: msg.value}(_isLimit, _triggerPrice, _stf.totalRaised);
        } else {
            if (_stf.status != StfStatus.OPENED && _stf.status != StfStatus.CLOSED) revert NoCloseActions();
            bool closed = IStfxGmx(_stfxAddress).closePosition{value: msg.value}(
                _isLimit, _size, _triggerPrice, _triggerAboveThreshold
            );
            if (closed) {
                _stf.status = StfStatus.CLOSED;
            }
        }

        emit CreatedPositionAgain(_stfxAddress, _isOpen, _triggerPrice);
    }

    /// @notice allows the stf contract to transfer back the collateral received from the dex after closing the position
    /// @notice also transfers the fees in case of a profit to the manager and the protocol
    /// @dev is called immediately after the stf's position has been closed completely on the dex
    /// @dev can be called by the `owner` of this contract or by the stf's `manager`
    /// @param _stfxAddress address of the stf
    function distributeProfits(address _stfxAddress) external override whenNotPaused {
        if (block.chainid != 42161) revert InvalidChainId(42161, block.chainid);
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if (msg.sender != _stf.manager && msg.sender != admin) revert NoAccess(_stf.manager, msg.sender);
        if (_stf.status != StfStatus.CLOSED) revert NotFinalised();

        (uint256 _remainingBalance, uint256 _managerFee, uint256 _protocolFee) =
            IStfxGmx(_stfxAddress).distributeProfits();
        _stf.remainingAmountAfterClose = _remainingBalance;
        _stf.status = StfStatus.DISTRIBUTED;
        isManagingFund[_stf.manager] = false;
        managerFees[_stfxAddress] = _managerFee;
        protocolFees[_stfxAddress] = _protocolFee;

        emit FeesTransferred(_stfxAddress, _remainingBalance, _managerFee, _protocolFee);
    }

    /// @notice get the `claimableAmount` of the investor from a particular stf
    /// @dev if theres no position opened, it'll return the deposited amount
    /// @dev after the position is closed, it'll calculate the `claimableAmount` depending on the weightage of the investor
    /// @param _stfxAddress address of the stf
    /// @param _investor address of the investor
    /// @return amount which can be claimed by the investor from a particular stf
    function claimableAmount(address _stfxAddress, address _investor) public view override returns (uint256 amount) {
        StfInfo storage _stf = stfInfo[_stfxAddress];

        if (_stf.claimed[_investor] || _stf.status == StfStatus.OPENED) {
            amount = 0;
        } else if (_stf.status == StfStatus.CANCELLED || _stf.status == StfStatus.NOT_OPENED) {
            amount = (_stf.totalRaised * _stf.userAmount[_investor] * 1e18) / (actualTotalRaised[_stfxAddress] * 1e18);
        } else if (_stf.status == StfStatus.DISTRIBUTED) {
            amount = (_stf.remainingAmountAfterClose * _stf.userAmount[_investor] * 1e18) / (actualTotalRaised[_stfxAddress] * 1e18);
        } else {
            amount = 0;
        }
    }

    /// @notice transfers the collateral to the investor depending on the investor's weightage to the totalRaised by the stf
    /// @dev will revert if the investor did not invest in the stf during the fundraisingPeriod
    /// @param _stfxAddress address of the invested stf
    function claim(address _stfxAddress) external override whenNotPaused {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if (_stf.status != StfStatus.DISTRIBUTED && _stf.status != StfStatus.CANCELLED) revert NotFinalised();

        uint256 amount = claimableAmount(_stfxAddress, msg.sender);
        if (amount < 1) revert ZeroTokenBalance();

        _stf.claimed[msg.sender] = true;
        _stf.claimAmount[msg.sender] = amount;

        IERC20(USDC).transfer(msg.sender, amount);
        emit Claimed(msg.sender, _stfxAddress, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice will change the status of the stf to `LIQUIDATED` and `isManagingFund(manager)` to false
    /// @dev can be called once an stf is liquidated from the dex
    /// @dev can only be called by the `owner`
    /// @param _stfxAddress address of the stf
    function closeLiquidatedVault(address _stfxAddress) external override onlyAdmin whenNotPaused {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if (_stf.status != StfStatus.OPENED) revert NotOpened();
        _stf.status = StfStatus.LIQUIDATED;
        isManagingFund[_stf.manager] = false;
        emit VaultLiquidated(_stfxAddress);
    }

    /// @notice will change the status of the stf to `CANCELLED` and `isManagingFund(manager)` to false
    /// @dev can be called if there was nothing raised during `fundraisingPeriod`
    /// @dev or can be called if the manager did not open any position within the `fundDeadline` (default - 72 hours)
    /// @dev can only be called by the `owner`
    /// @param _stfxAddress address of the stf
    function cancelVault(address _stfxAddress) external override onlyAdmin whenNotPaused {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if (_stf.status != StfStatus.NOT_OPENED) revert OpenPosition();
        if (_stf.totalRaised == 0) {
            if (block.timestamp <= _stf.endTime) revert BelowMin(_stf.endTime, block.timestamp);
        } else {
            if (block.timestamp <= _stf.endTime + _stf.fundDeadline) revert BelowMin(_stf.endTime, block.timestamp);
        }
        _stf.status = StfStatus.CANCELLED;
        isManagingFund[_stf.manager] = false;
        emit NoFillVaultClosed(_stfxAddress);
    }

    /// @notice the manager can cancel the stf if they want, after fundraising
    /// @dev can be called by the `manager`
    /// @param _stfxAddress address of the stf
    function cancelStfByManager(address _stfxAddress) external override whenNotPaused {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if (msg.sender != _stf.manager) revert NoAccess(_stf.manager, msg.sender);
        if (_stf.status != StfStatus.NOT_OPENED) revert OpenPosition();
        if (block.timestamp > _stf.endTime + _stf.fundDeadline) revert CantClose();

        _stf.fundDeadline = 0;
        _stf.endTime = 0;
        _stf.status = StfStatus.CANCELLED;
        isManagingFund[_stf.manager] = false;
        emit NoFillVaultClosed(_stfxAddress);
    }

    /// @notice cancel an open limit order if not executed within `fundDeadline` (72 hours)
    /// @dev can be called by the `manager` and by the `admin`, will check if there's an open limit order created and cancel it
    /// @param _stfxAddress address of the stf
    /// @param _orderIndex the order index from the dex
    function cancelStfAfterOpening(address _stfxAddress, uint256 _orderIndex) external override whenNotPaused {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if(msg.sender != _stf.manager && msg.sender != admin) revert NoAccess(_stf.manager, msg.sender);

        if(msg.sender == admin) {
            if (block.timestamp <= _stf.endTime + _stf.fundDeadline) revert CantClose();
        }

        _stf.fundDeadline = 0;
        if(!shouldCancelOpenLimitOrder(_stfxAddress)) revert CantClose();
        uint256 remainingBalance = IStfxGmx(_stfxAddress).cancelOrder(_orderIndex, true);

        _stf.totalRaised = remainingBalance;
        _stf.remainingAmountAfterClose = remainingBalance;
        _stf.status = StfStatus.CANCELLED;
        isManagingFund[_stf.manager] = false;

        emit NoFillVaultClosed(_stfxAddress);
    }

    /// @notice cancel the stf after a month and close the position as a market order
    /// @dev can only be called by the `admin` after the `maxDeadlineForPosition`, defaults to 30 days
    /// @param _stfxAddress address of the stf
    /// @param hasCloseOrder if true, the manager has created a close limit order
    /// @param _orderIndex the order index from the dex
    /// @param _triggerPrice price input depending on the latest price from the dex and whether its a limit or a market order
    /// @param _triggerAboveThreshold bool to check if the `triggerPrice` is above or below the `currentPrice`,
    function cancelStfAfterPositionDeadline(
        address _stfxAddress, 
        bool hasCloseOrder,
        uint256 _orderIndex,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external payable override whenNotPaused {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        (uint256 _size,,,,,,) = getPosition(_stfxAddress);

        if(block.timestamp <= maxDeadlineForPosition) revert BelowMin(maxDeadlineForPosition, block.timestamp);
        if(msg.sender != admin) revert CantClose();
        if(_stf.status != StfStatus.CLOSED && _stf.status != StfStatus.OPENED) revert CantClose();
        if(_size < 1) revert NoOpenPositions();

        if(hasCloseOrder) {
            uint256 remainingBalance = IStfxGmx(_stfxAddress).cancelOrder(_orderIndex, false);
        }

        IStfxGmx(_stfxAddress).closePosition{value: msg.value}(
            false, _size, _triggerPrice, _triggerAboveThreshold
        );
        _stf.status = StfStatus.CLOSED;
        
        emit VaultClosed(_stfxAddress, _size, false, _triggerPrice, true);
    }

    /*//////////////////////////////////////////////////////////////
                            SETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice set the max capacity of collateral which can be raised per stf
    /// @dev can only be called by the `owner`
    /// @param _capacity max capacity of the collateral which can be raised per stf
    function setCapacityPerStf(uint256 _capacity) external override onlyOwner whenNotPaused {
        if (_capacity < 1) revert ZeroAmount();
        capacityPerStf = _capacity;
        emit CapacityPerStfChanged(_capacity);
    }

    /// @notice set the min investment of collateral an investor can invest per stf
    /// @dev can only be called by the `owner`
    /// @param _amount min investment of collateral an investor can invest per stf
    function setMinInvestmentAmount(uint256 _amount) external override onlyOwner whenNotPaused {
        if (_amount < 1) revert ZeroAmount();
        minInvestmentAmount = _amount;
        emit MinInvestmentAmountChanged(_amount);
    }

    /// @notice set the max investment of collateral an investor can invest per stf
    /// @dev can only be called by the `owner`
    /// @param _amount max investment of collateral an investor can invest per stf
    function setMaxInvestmentAmount(uint256 _amount) external override onlyOwner whenNotPaused {
        if (_amount <= minInvestmentAmount) revert BelowMin(minInvestmentAmount, _amount);
        maxInvestmentAmount = _amount;
        emit MaxInvestmentAmountChanged(_amount);
    }

    /// @notice set the max leverage a manager can use when creating an stf
    /// @dev can only be called by the `owner`
    /// @param _maxLeverage max leverage a manager can use when creating an stf
    function setMaxLeverage(uint256 _maxLeverage) external override onlyOwner whenNotPaused {
        if (_maxLeverage <= 1e6) revert AboveMax(1e6, _maxLeverage);
        maxLeverage = _maxLeverage;
        emit MaxLeverageChanged(_maxLeverage);
    }

    function setMinLeverage(uint256 _minLeverage) external override onlyOwner whenNotPaused {
        if (_minLeverage < 1e6) revert BelowMin(1e16, _minLeverage);
        minLeverage = _minLeverage;
        emit MinLeverageChanged(_minLeverage);
    }

    /// @notice set the max fundraising period a manager can use when creating an stf
    /// @dev can only be called by the `owner`
    /// @param _maxFundraisingPeriod max fundraising period a manager can use when creating an stf
    function setMaxFundraisingPeriod(uint256 _maxFundraisingPeriod) external onlyOwner whenNotPaused {
        if (_maxFundraisingPeriod < 15 minutes) revert BelowMin(15 minutes, _maxFundraisingPeriod);
        maxFundraisingPeriod = _maxFundraisingPeriod;
        emit MaxFundraisingPeriodChanged(_maxFundraisingPeriod);
    }

    /// @notice set the max deadline a position can be open for an stf
    /// @dev can only be called by the `owner`
    /// @param _maxDeadlineForPosition max deadline a position can be open for an stf (default - 30 days)
    function setMaxDeadlineForPosition(uint256 _maxDeadlineForPosition) external onlyOwner whenNotPaused {
        if(_maxDeadlineForPosition < 1 days) revert BelowMin(1 days, _maxDeadlineForPosition);
        maxDeadlineForPosition = _maxDeadlineForPosition;
        emit MaxDeadlineForPositionChanged(_maxDeadlineForPosition);
    }

    /// @notice set the manager fee percent to calculate the manager fees on profits depending on the governance
    /// @dev can only be called by the `owner`
    /// @param newManagerFee the percent which is used to calculate the manager fees on profits
    function setManagerFee(uint256 newManagerFee) external override onlyOwner whenNotPaused {
        managerFee = newManagerFee;
        emit ManagerFeeChanged(newManagerFee);
    }

    /// @notice set the protocol fee percent to calculate the protocol fees on profits depending on the governance
    /// @dev can only be called by the `owner`
    /// @param newProtocolFee the percent which is used to calculate the protocol fees on profits
    function setProtocolFee(uint256 newProtocolFee) external override onlyOwner whenNotPaused {
        protocolFee = newProtocolFee;
        emit ProtocolFeeChanged(newProtocolFee);
    }

    /// @notice set the new owner of the StfxVault contract
    /// @dev can only be called by the current `owner`
    /// @param newOwner the new owner of the StfxVault contract
    function setOwner(address newOwner) external override onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
        emit OwnerChanged(newOwner);
    }

    /// @notice set the new stfx implementation contract address for creating stfs
    /// @dev can only be called by the `owner`
    /// @param stfx the new stfx implementation contract address for creating stfs
    function setStfxImplementation(address stfx) external override onlyOwner {
        stfxImplementation = stfx;
        emit StfxImplementationChanged(stfx);
    }

    /// @notice set the new reader contract address
    /// @dev can only be called by the `owner`
    /// @param _reader the new reader contract address
    function setReader(address _reader) external override onlyOwner {
        reader = IReader(_reader);
        emit ReaderAddressChanged(_reader);
    }

    /// @notice set the `fundDeadline` for a particular stf to cancel the vault early if needed
    /// @dev can only be called by the `owner` or the `manager` of the stf
    /// @param _stfxAddress address of the stf
    /// @param newFundDeadline new fundDeadline
    function setFundDeadline(address _stfxAddress, uint256 newFundDeadline) external override {
        StfInfo storage _stf = stfInfo[_stfxAddress];
        if (msg.sender != _stf.manager && msg.sender != owner) revert NoAccess(_stf.manager, msg.sender);
        if (newFundDeadline > 72 hours) revert AboveMax(72 hours, newFundDeadline);
        _stf.fundDeadline = newFundDeadline;
        emit FundDeadlineChanged(_stfxAddress, newFundDeadline);
    }

    /// @notice set the usdc address
    /// @dev can only be called by the `owner`
    /// @param _usdc the usdc address
    function setUsdc(address _usdc) external onlyOwner {
        if (_usdc == address(0)) revert ZeroAddress();
        USDC = _usdc;
        emit UsdcAddressChanged(_usdc);
    }

    /// @notice set the weth address
    /// @dev can only be called by the `owner`
    /// @param _weth the weth address
    function setWeth(address _weth) external onlyOwner {
        if (_weth == address(0)) revert ZeroAddress();
        WETH = _weth;
        emit WethAddressChanged(_weth);
    }

    /// @notice set the admin address
    /// @dev can only be called by the `owner`
    /// @param _admin the admin address
    function setAdmin(address _admin) external onlyOwner {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
        emit AdminChanged(_admin);
    }

    /// @notice set the treasury address
    /// @dev can only be called by the `owner`
    /// @param _treasury the treasury address
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        emit TreasuryChanged(_treasury);
    }

    /// @notice set the referralCode from the dex depending on the governance
    /// @dev can only be called by the `owner`
    /// @param _referralCode the referralCode from the dex depending on the governance
    function setReferralCode(bytes32 _referralCode) external onlyOwner {
        referralCode = _referralCode;
        emit ReferralCodeChanged(_referralCode);
    }

    /// @notice Set the `status` of an stf in case of an emergency
    /// @dev is called only from the `Stfx` contract and reverts if called by another address
    /// @param _status new `status` of the stf
    function setStfStatus(StfStatus _status) external override {
        StfInfo storage _stf = stfInfo[msg.sender];
        if(_stf.stfxAddress != msg.sender) revert ZeroAddress();
        _stf.status = _status;
        emit StfStatusUpdate(msg.sender, _status);
    }

    /// @notice Set the `totalRaised` of an stf in case of an emergency
    /// @dev is called only from the `Stfx` contract and reverts if called by another address
    /// @param _totalRaised new `totalRaised` of the stf
    function setStfTotalRaised(uint256 _totalRaised) external override {
        StfInfo storage _stf = stfInfo[msg.sender];
        if(_stf.stfxAddress != msg.sender) revert ZeroAddress();
        _stf.totalRaised = _totalRaised;
        emit StfTotalRaisedUpdate(msg.sender, _totalRaised);
    }

    /// @notice Set the `remainingAmountAfterClose` of an stf in case of an emergency
    /// @dev is called only from the `Stfx` contract and reverts if called by another address
    /// @param _remainingBalance new `remainingAmountAfterClose` of the stf
    function setStfRemainingBalance(uint256 _remainingBalance) external override {
        StfInfo storage _stf = stfInfo[msg.sender];
        if(_stf.stfxAddress != msg.sender) revert ZeroAddress();
        _stf.remainingAmountAfterClose = _remainingBalance;
        emit StfRemainingBalanceUpdate(msg.sender, _remainingBalance);
    }

    /// @notice Set the `isManagingFund` state to true or false depending on the emergency
    /// @dev Can only be called by the owner
    /// @param _manager address of the manager
    /// @param _isManaging true if already managing an stf and false if not managing an stf
    function setIsManagingFund(address _manager, bool _isManaging) external override onlyOwner {
        isManagingFund[_manager] = _isManaging;
        emit ManagingFundUpdate(_manager, _isManaging);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfer `Eth` from this contract to the `receiver` in case of emergency
    /// @dev Can be called only by the `owner`
    /// @param receiver address of the `receiver`
    /// @param amount amount to be withdrawn
    function withdrawEth(address receiver, uint256 amount) external override onlyOwner {
        if (receiver == address(0)) revert ZeroAddress();
        uint256 balance = address(this).balance;
        if(amount > balance) revert AboveMax(balance, amount);
        payable(receiver).transfer(amount);
        emit WithdrawEth(receiver, amount);
    }

    /// @notice Transfer `ERC20` token from this contract to the `receiver` in case of emergency
    /// @dev Can be called only by the `owner`
    /// @param token address of the `ERC20` token
    /// @param receiver address of the `receiver`
    /// @param amount amount to be withdrawn
    function withdrawToken(address token, address receiver, uint256 amount) external override onlyOwner {
        if (receiver == address(0)) revert ZeroAddress();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if(amount > balance) revert AboveMax(balance, amount);
        IERC20(token).transfer(receiver, amount);
        emit WithdrawToken(token, receiver, amount);
    }

    /// @notice Transfer `ERC20` token from this contract to the `receiver` in case of emergency
    /// @dev Can be called only by the `owner`
    /// @param _stfxAddress address of the stf
    /// @param receiver address of the `receiver`
    /// @param isEth bool true if withdrawing `Eth` from `Stfx` contract, else withdrawing ERC20 `token`
    /// @param token address of the `ERC20` token
    function withdrawFromStf(
        address _stfxAddress, 
        address receiver, 
        bool isEth, 
        address token,
        uint256 amount
    )
        external
        override
        onlyOwner
    {
        if (receiver == address(0)) revert ZeroAddress();
        uint256 balance;
        if (isEth) {
            balance = address(_stfxAddress).balance;
        } else {
            balance = IERC20(token).balanceOf(_stfxAddress);
        }
        if(amount > balance) revert AboveMax(balance, amount);
        IStfxGmx(_stfxAddress).withdraw(receiver, isEth, token, amount);
        emit WithdrawFromStf(_stfxAddress, receiver, isEth, token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          PAUSE/UNPAUSE
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause contract
    /// @dev can only be called by the `owner` when the contract is not paused
    function pause() public onlyAdmin whenNotPaused {
        _pause();
    }

    /// @notice Unpause contract
    /// @dev can only be called by the `owner` when the contract is paused
    function unpause() public onlyAdmin whenPaused {
        _unpause();
    }
}

