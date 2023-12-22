// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {Ownable} from "./Ownable.sol";
import {Initializable} from "./Initializable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

contract AuctionTreasury is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant RATIO_PRECISION = 1000;

    IERC20 public LVL;
    IERC20 public USDT;

    address public LVLAuctionFactory;
    address public admin;
    address public cashTreasury;
    address public lpReserve;
    uint256 public usdtToReserveRatio;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _cashTreasury,
        address _lpReserve,
        address _lvl,
        address _usdt
    ) external initializer {
        __Ownable_init();
        require(_lvl != address(0), "Invalid address");
        require(_cashTreasury != address(0), "Invalid address");
        require(_usdt != address(0), "Invalid address");
        require(_lpReserve != address(0), "Invalid address");
        cashTreasury = _cashTreasury;
        LVL = IERC20(_lvl);
        USDT = IERC20(_usdt);
        lpReserve = _lpReserve;
        usdtToReserveRatio = 750;
    }

    function transferLVL(address _for, uint256 _amount) external {
        require(msg.sender == LVLAuctionFactory, "only LVLAuctionFactory");
        LVL.safeTransfer(_for, _amount);
        emit LVLGranted(_for, _amount);
    }

    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Invalid address");
        admin = _admin;
        emit AdminSet(_admin);
    }

    function setLVLAuctionFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "Invalid address");
        LVLAuctionFactory = _factory;
        emit LVLAuctionFactorySet(_factory);
    }

    function distribute() external {
        require(
            msg.sender == admin || msg.sender == owner(),
            "Only Owner or Admin can operate"
        );
        uint256 _usdtBalance = USDT.balanceOf(address(this));
        uint256 _amountToTreasury = (_usdtBalance * usdtToReserveRatio) /
            RATIO_PRECISION;
        uint256 _amountToLP = _usdtBalance - _amountToTreasury;

        // 1. split to Treasury
        if (_amountToTreasury > 0) {
            require(cashTreasury != address(0), "Invalid address");
            USDT.safeTransfer(cashTreasury, _amountToTreasury);
        }

        // 2. convert to LP
        if (_amountToLP > 0) {
            require(lpReserve != address(0), "Invalid address");
            USDT.safeTransfer(lpReserve, _amountToLP);
        }
    }

    function recoverFund(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
        emit FundRecovered(_token, _to, _amount);
    }

    /* ========== EVENTS ========== */
    event AdminSet(address _admin);
    event LVLGranted(address _for, uint256 _amount);
    event LGOGranted(address _for, uint256 _amount);
    event LVLAuctionFactorySet(address _factory);
    event LGOAuctionFactorySet(address _factory);
    event FundRecovered(address indexed _token, address _to, uint256 _amount);
    event FundWithdrawn(address indexed _token, address _to, uint256 _amount);
}

