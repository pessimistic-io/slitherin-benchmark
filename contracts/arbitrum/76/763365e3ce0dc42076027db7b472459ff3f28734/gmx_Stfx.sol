// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "./Test.sol";
import {StfxVault} from "./StfxVault.sol";
import {IERC20} from "./IERC20.sol";
import {IStfx} from "./IStfx.sol";
import {IStfxGmx} from "./IStfxGmx.sol";
import {IReader} from "./IReader.sol";
import {IGmxVault} from "./IGmxVault.sol";
import {IGmxReader} from "./IGmxReader.sol";
import {IGmxRouter} from "./IGmxRouter.sol";
import {IGmxPositionRouter} from "./IGmxPositionRouter.sol";
import {IGmxOrderBook} from "./IGmxOrderBook.sol";

error Initialized();
error NotInitialized();
error ZeroInput();
error ZeroBalance();
error NotEqual(uint256 desired, uint256 given);
error AboveMax(uint256 max, uint256 given);
error BelowMin(uint256 min, uint256 given);
error NoAccess(address desired, address given);
error AlreadyOpened();

/// @title Stfx
/// @author 7811, abhi3700
/// @notice Contract which acts as the STF (Single Trade Fund)
/// @dev this contract is used as the `account` on the dex
contract Stfx is IStfx, IStfxGmx {
    // usdc address
    address private USDC;
    // weth address
    address private WETH;

    // bool to check if `initialize()` has already been called
    bool private initialized;
    // address of the manager
    address public manager;

    // contains all the details of the Stf
    // check `IStfxStorage.Stf`
    Stf public stf;
    // StfxVault contract
    // check `StfxVault.sol`
    StfxVault public vault;
    // Stfx Reader contract - contains view functions
    // check `./Reader.sol`
    IReader public reader;

    bytes32 public referralCode;
    // remaining collateral which we receive from the dex after closing the trade
    uint256 public remainingBalance;
    // total number of close limit orders created
    uint256 public totalCloseOrdersCreated;

    /// @notice modifier for ensuring functionality can only be called once initialized
    modifier onlyInit() {
        if (!initialized) revert NotInitialized();
        _;
    }

    /// @notice modifier for the function to only be called by the StfxVault contract
    modifier onlyVault() {
        if (msg.sender != address(vault)) revert NoAccess(address(vault), msg.sender);
        _;
    }

    /// @notice modifier for the function to only be called by the manager
    modifier onlyManager() {
        (, address _manager,,,,,) = vault.stfInfo(address(this));
        if (msg.sender != _manager) revert NoAccess(_manager, msg.sender);
        _;
    }

    function getStf() external view returns (Stf memory) {
        return stf;
    }

    /// @notice initialize the STF
    /// @dev can only be initialized once
    /// @param _stf the `Stf` struct from `IStfxStorage` which contains the info of the stf
    /// @param _manager address of the manager who created the Stf
    /// @param _usdc USDC contract address
    /// @param _weth WETH contract address
    /// @param _reader `Reader` contract address
    function initialize(Stf calldata _stf, address _manager, address _usdc, address _weth, address _reader)
        external
        override
    {
        if (initialized) revert Initialized();
        initialized = true;

        stf = _stf;
        manager = _manager;
        vault = StfxVault(msg.sender);
        USDC = _usdc;
        WETH = _weth;
        reader = IReader(_reader);

        emit Initialize(_manager, address(this), msg.sender);
    }

    /// @notice Creates an open position or an open order on GMX depending on the input by the manager
    /// @dev can only be called by the StfxVault contract
    /// @dev is payable since GMX has a small fee in ETH, which can be obtained by `IGmxPositionRouter.minExecutionFee();`
    /// @param isLimit if true, then its a limit order, else a market order
    /// @param _triggerPrice price input depending on the latest price from the dex and whether its a limit or a market order
    /// @param _totalRaised total raised amount by the Stf which will be transferred from StfxVault contract
    function openPosition(bool isLimit, uint256 _triggerPrice, uint256 _totalRaised)
        external
        payable
        override
        onlyInit
        onlyVault
    {
        (uint256 size,,,,,,) = vault.getPosition(address(this));
        if (size > 1) revert AlreadyOpened();
        if (_triggerPrice < 1) revert ZeroInput();
        address[] memory _dex = reader.getDex();

        /// GMX checks if `msg.value >= fee` for closing positions, so we need 1 more WEI to pass.
        uint256 _fee = IGmxPositionRouter(_dex[2]).minExecutionFee();
        if (msg.value < _fee) revert NotEqual(_fee, msg.value);

        address[] memory _path;
        if (!stf.tradeDirection) {
            _path = new address[](1);
            _path[0] = USDC;
        } else {
            _path = new address[](2);
            _path[0] = USDC;
            _path[1] = stf.baseToken;
        }

        IERC20(USDC).approve(_dex[1], _totalRaised);
        if (isLimit) {
            IGmxRouter(_dex[1]).approvePlugin(_dex[3]);
            IGmxOrderBook(_dex[3]).createIncreaseOrder{value: _fee}(
                _path,
                _totalRaised,
                stf.baseToken,
                0,
                stf.leverage * _totalRaised * 1e18,
                stf.tradeDirection ? stf.baseToken : USDC,
                stf.tradeDirection,
                _triggerPrice * 1e24,
                stf.tradeDirection ? false : true,
                _fee,
                false
            );
        } else {
            IGmxRouter(_dex[1]).approvePlugin(_dex[2]);
            IGmxPositionRouter(_dex[2]).createIncreasePosition{value: _fee}(
                _path,
                stf.baseToken,
                _totalRaised,
                0,
                stf.leverage * _totalRaised * 1e18,
                stf.tradeDirection,
                _triggerPrice * 1e24,
                _fee,
                vault.referralCode(),
                address(0)
            );
        }
    }

    /// @notice Creates a close position or a close order on GMX depending on the input by the manager
    /// @dev can only be called by the StfxVault contract
    /// @dev is payable since GMX has a small fee in ETH, which can be obtained by `IGmxPositionRouter.minExecutionFee();`
    /// @dev the msg.value should be > fee and not >= fee (which means it has to be fee + 1) for it to succeed, GMX is designed that way
    /// @param isLimit if true, then its a limit order, else a market order
    /// @param _size the position size which the manager wants to close
    /// @param _triggerPrice price input depending on the latest price from the dex and whether its a limit or a market order
    /// @param _triggerAboveThreshold bool to check if the `triggerPrice` is above or below the `currentPrice`, used for SL/TP
    /// @return closed - true if the function creates a close position or a close order successfully with the entire position size which is open
    ///         false if the position is only closed partially
    function closePosition(bool isLimit, uint256 _size, uint256 _triggerPrice, bool _triggerAboveThreshold)
        external
        payable
        override
        onlyInit
        onlyVault
        returns (bool closed)
    {
        (uint256 size,,,,,,) = vault.getPosition(address(this));
        if (_size != size) revert NotEqual(size, _size);
        if (_triggerPrice < 1) revert ZeroInput();

        address[] memory _dex = reader.getDex();

        /// GMX checks if `msg.value > fee` for closing positions, so we need 1 more WEI to pass.
        uint256 _fee = IGmxPositionRouter(_dex[2]).minExecutionFee() + 1;
        if (msg.value < _fee) revert BelowMin(_fee, msg.value);

        address[] memory _path;
        if (!stf.tradeDirection) {
            _path = new address[](1);
            _path[0] = USDC;
        } else {
            _path = new address[](2);
            _path[0] = stf.baseToken;
            _path[1] = USDC;
        }

        _triggerPrice *= 1e24;

        if (isLimit) {
            IGmxRouter(_dex[1]).approvePlugin(_dex[3]);
            IGmxOrderBook(_dex[3]).createDecreaseOrder{value: _fee}(
                stf.baseToken, _size, stf.tradeDirection ? stf.baseToken : USDC, 0, stf.tradeDirection, _triggerPrice, _triggerAboveThreshold
            );
            totalCloseOrdersCreated += 1;
        } else {
            IGmxRouter(_dex[1]).approvePlugin(_dex[2]);
            IGmxPositionRouter(_dex[2]).createDecreasePosition{value: _fee}(
                _path, 
                stf.baseToken, 
                0, 
                _size, 
                stf.tradeDirection, 
                address(this), 
                _triggerPrice, 
                0, 
                _fee, 
                false, 
                address(0)
            );
        }

        return true;
    }

    /// @notice cancels an order which the manager had already created
    /// @dev can only be called by the StfxVault contract
    /// @dev transfers the remaining amount back to the StfxVault contract
    /// @dev in case of cancelling long open orders, it swaps back to the collateral which is used
    /// @dev it also transfers back the `fee` to the `manager` which was paid during opening or closing the order in ETH
    /// @param _orderIndex the index of the order which has to be cancelled, can be obtained from GMX
    /// @param _isOpen if true, the manager can cancel an open order, else, the manager can cancel a close order
    /// @return remaining amount of the collateral which we get back from GMX
    function cancelOrder(uint256 _orderIndex, bool _isOpen) external onlyInit onlyVault returns (uint256 remaining) {
        address[] memory _dex = reader.getDex();
        if (_isOpen) {
            IGmxOrderBook(_dex[3]).cancelIncreaseOrder(_orderIndex);
            if (stf.tradeDirection) {
                if (stf.baseToken == WETH) {
                    uint256 _fee = IGmxPositionRouter(_dex[2]).minExecutionFee();
                    swapEthToTokens((address(this).balance - _fee));
                } else {
                    uint256 baseTokenBalance = IERC20(stf.baseToken).balanceOf(address(this));
                    swapTokens(stf.baseToken, baseTokenBalance);
                }
            }
        } else {
            (uint256 _size,,,,,,) = vault.getPosition(address(this));
            if (_size < 1) revert ZeroBalance();
            IGmxOrderBook(_dex[3]).cancelDecreaseOrder(_orderIndex);
            if (totalCloseOrdersCreated > 1) {
                vault.setStfStatus(StfStatus.CLOSED);
            }
            totalCloseOrdersCreated -= 1;
        }

        uint256 balance = address(this).balance;
        remaining = IERC20(USDC).balanceOf(address(this));

        if (balance > 0) payable(manager).transfer(balance);

        if (remaining > 0) IERC20(USDC).transfer(address(vault), remaining);
    }

    /// @notice distributes the fees on profits to manager and protocol
    /// @notice and transfers back the remaining collateral to the StfxVault contract for the investors to claim back
    /// @dev gets the fee percent for manager and protocol from the StfxVault contract
    /// @dev if the contract receives baseToken from GMX when closing the trade, then it is swapped back to the collateral token
    /// @return remaining - the remaining collateral balance after profit or loss which is transferred to the StfxVault contract
    /// @return managerFee - the fee which is transferred to the manager in case of a profit
    /// @return protocolFee - the fee which is transferred to the protocol in case of a profit
    function distributeProfits()
        public
        override
        onlyInit
        onlyVault
        returns (uint256 remaining, uint256 managerFee, uint256 protocolFee)
    {
        Stf memory _stf = stf;
        uint256 _totalRaised = vault.actualTotalRaised(address(this));

        uint256 baseTokenBalance = IERC20(_stf.baseToken).balanceOf(address(this));
        address[] memory path = new address[](2);
        path[1] = USDC;

        if (address(this).balance > 0) swapEthToTokens(address(this).balance);
        if (baseTokenBalance > 0) swapTokens(_stf.baseToken, baseTokenBalance);

        uint256 usdcBalance = IERC20(USDC).balanceOf(address(this));
        if (usdcBalance < 1) revert ZeroBalance();

        if (usdcBalance > _totalRaised) {
            uint256 profits = usdcBalance - _totalRaised;
            managerFee = (profits * vault.managerFee()) / 100e18;
            protocolFee = (profits * vault.protocolFee()) / 100e18;

            IERC20(USDC).transfer(manager, managerFee);
            IERC20(USDC).transfer(vault.treasury(), protocolFee);

            remaining = usdcBalance - (managerFee + protocolFee);
        } else {
            remaining = usdcBalance;
        }

        remainingBalance = remaining;

        IERC20(USDC).transfer(address(vault), remaining);
    }

    /// @notice used to withdraw eth + erc20s from this contract
    function withdraw(address receiver, bool isEth, address token, uint256 amount)
        external
        override
        onlyInit
        onlyVault
    {
        if (isEth) {
            payable(receiver).transfer(amount);
        } else {
            IERC20(token).transfer(receiver, amount);
        }
    }

    /// @notice changes the status of the stf
    /// @dev can be called only by `StfxVault.admin`
    /// @param _status new `status` of the stf
    function changeStfStatus(StfStatus _status) external override {
        if (msg.sender != vault.admin()) revert NoAccess(vault.admin(), msg.sender);
        vault.setStfStatus(_status);
    }

    /// @notice can be called for swapping ETH to USDC on GMX
    /// @dev internal function
    /// @param amount amount of ETH which needs to be swapped
    function swapEthToTokens(uint256 amount) internal {
        address[] memory _dex = reader.getDex();
        (uint256 amountOut,) = IGmxReader(_dex[4]).getAmountOut(IGmxVault(_dex[0]), WETH, USDC, amount);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        IGmxRouter(_dex[1]).swapETHToTokens{value: amount}(path, amountOut, address(this));
    }

    /// @notice can be called for swapping any ERC20 token to USDC on GMX
    /// @dev internal function
    /// @param amount amount of the ERC20 token which needs to be swapped
    function swapTokens(address token, uint256 amount) internal {
        address[] memory _dex = reader.getDex();
        (uint256 amountOut,) = IGmxReader(_dex[4]).getAmountOut(IGmxVault(_dex[0]), token, USDC, amount);

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = USDC;

        IERC20(token).approve(_dex[1], amount);
        IGmxRouter(_dex[1]).swap(path, amount, amountOut, address(this));
    }

    /// @notice fallback function required when GMX sends back the `fee` in ETH when cancelling an order
    /// @dev fallback function does not do anything on receiving ETH
    receive() external payable {}
}

