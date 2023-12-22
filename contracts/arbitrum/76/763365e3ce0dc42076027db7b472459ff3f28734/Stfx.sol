// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import {StfxVault} from "./StfxVault.sol";
import {IERC20} from "./IERC20.sol";
import {IStfx} from "./IStfx.sol";
import {IStfxPerp} from "./IStfxPerp.sol";
import {IMarketRegistry} from "./IMarketRegistry.sol";
import {IBaseToken} from "./IBaseToken.sol";
import {IVault} from "./IVault.sol";
import {IClearingHouse} from "./IClearingHouse.sol";
import {IReader} from "./IReader.sol";

contract Stfx is IStfx, IStfxPerp {
    address private USDC;
    address private WETH;

    bool private calledInitialize;
    bool private calledOpen;

    address public manager;

    Stf public stf;
    StfxVault public vault;
    IReader public reader;

    bytes32 public referralCode;

    uint256 public remainingBalance;
    uint256 public managerFee;
    uint256 public protocolFee;

    /// @notice modifier to make sure the initalize() is called only once
    modifier initOnce() {
        require(!calledInitialize, "can only initialize once");
        calledInitialize = true;
        _;
    }

    modifier onlyVault() {
        require(msg.sender == address(vault), "onlyVault");
        _;
    }

    modifier openOnce() {
        require(!calledOpen, "can only open once");
        calledOpen = true;
        _;
    }

    function initialize(Stf calldata _stf, address _manager, address _usdc, address _weth, address _reader)
        external
        override
        initOnce
    {
        stf = _stf;
        manager = _manager;
        vault = StfxVault(msg.sender);
        USDC = _usdc;
        WETH = _weth;
        reader = IReader(_reader);
        
        emit Initialize(_manager, address(this), msg.sender);
    }

    function openPosition() external override onlyVault openOnce returns (bool) {
        Stf memory _stf = stf;
        address[] memory _dex = reader.getDex();

        (,, uint256 _totalRaised,,,,) = vault.stfInfo(address(this));

        IERC20(USDC).approve(_dex[0], _totalRaised);
        IVault(_dex[0]).deposit(USDC, _totalRaised);

        if (_stf.tradeDirection) {
            // long
            IClearingHouse(_dex[2]).openPosition(
                IClearingHouse.OpenPositionParams({
                    baseToken: _stf.baseToken,
                    isBaseToQuote: !_stf.tradeDirection,
                    isExactInput: true,
                    amount: _totalRaised * _stf.leverage * 1e12,
                    oppositeAmountBound: 0,
                    sqrtPriceLimitX96: 0,
                    deadline: block.timestamp + 900,
                    referralCode: referralCode
                })
            );
        } else {
            // short
            IClearingHouse(_dex[2]).openPosition(
                IClearingHouse.OpenPositionParams({
                    baseToken: _stf.baseToken,
                    isBaseToQuote: !_stf.tradeDirection,
                    isExactInput: false,
                    amount: _totalRaised * _stf.leverage * 1e12,
                    oppositeAmountBound: 0,
                    sqrtPriceLimitX96: 0,
                    deadline: block.timestamp + 900,
                    referralCode: referralCode
                })
            );
        }
        return true;
    }

    function closePosition() external override onlyVault returns (bool) {
        Stf memory _stf = stf;
        address[] memory _dex = reader.getDex();

        IClearingHouse(_dex[2]).closePosition(
            IClearingHouse.ClosePositionParams({
                baseToken: _stf.baseToken,
                oppositeAmountBound: 0,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 900,
                referralCode: referralCode
            })
        );

        uint256 collateralBalance = IVault(_dex[0]).getFreeCollateral(address(this));
        IVault(_dex[0]).withdraw(USDC, collateralBalance);
        uint256 usdcBalance = IERC20(USDC).balanceOf(address(this));

        uint256 profits;

        (,, uint256 _totalRaised,,,,) = vault.stfInfo(address(this));

        if (usdcBalance > _totalRaised) {
            profits = usdcBalance - _totalRaised;
            managerFee = (profits * vault.managerFee()) / 100e18;
            protocolFee = (profits * vault.protocolFee()) / 100e18;

            IERC20(USDC).transfer(manager, managerFee);
            IERC20(USDC).transfer(vault.owner(), protocolFee);

            remainingBalance = IERC20(USDC).balanceOf(address(this));
        } else {
            remainingBalance = usdcBalance;
        }

        IERC20(USDC).transfer(address(vault), remainingBalance);
        return true;
    }
}

