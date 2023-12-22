// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./Ownable.sol";
import "./Address.sol";

import {ICopyTraderAccount} from "./gmxInterfaces.sol";

import "./CopyTraderAccount.sol";

contract CopyTraderIndex is Ownable {
    using Address for address;

    /* ========== CONSTANTS ========== */
    uint256 public MIN_COLLATERAL_USD = 10e30; // 10 USD  : decimals 30
    uint256 public CT_EXECUTE_FEE = 70000000000000; // decimal 18  to-> backend
    uint256 public COPY_TRADER_FEE = 150; // decimal 18  to->treasury
    address private deadAddress = address(0x000000000000000000000000000000000000dEaD);

    address private constant _weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address public constant gmxVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    address public constant gmxRouter = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;
    address public constant gmxPositionRouter = 0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868;

    /* ========== STATE VARIABLES ========== */
    address public TREASURY = address(0);
    address public BACKEND = address(0);
    mapping(address => address) private _CopyAccountList;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _treasury, address _backend) {
        TREASURY = _treasury;
        BACKEND = _backend;
    }

    /* ========== VIEWS ========== */
    function getCopyTraderAccount(address _owner) external view returns (address) {
        return _CopyAccountList[_owner];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function withdrawToken(address _tokenAddr, uint256 _amount) external onlyOwner {
        require(_amount > 0, "must be greater than zero");
        uint256 balanceOfToken = IERC20(_tokenAddr).balanceOf(address(this));
        uint256 transAmount = _amount;
        if (_amount > balanceOfToken) {
            transAmount = balanceOfToken;
        }
        IERC20(_tokenAddr).transfer(owner(), transAmount);
    }

    function setMinCollateralUsd(uint256 _min_collateral_usd) external onlyOwner {
        require(_min_collateral_usd > 0, "must be greater thatn zero");
        MIN_COLLATERAL_USD = _min_collateral_usd; // decimals 30
    }

    function setCopyTraderFee(uint256 _copy_trader_fee) external onlyOwner {
        require(_copy_trader_fee > 0 && _copy_trader_fee < 5000, "must be: 0 < fee < 5000 ( 0% < fee < 50%)");
        MIN_COLLATERAL_USD = _copy_trader_fee; // decimals 2
    }

    function setCtExecuteFee(uint256 _ct_execute_fee) external onlyOwner {
        require(_ct_execute_fee > 0, "must be greater thatn zero");
        CT_EXECUTE_FEE = _ct_execute_fee; // decimals 18
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != deadAddress && _treasury != address(0), "treasury account error");
        TREASURY = _treasury;
    }

    function setBackend(address _backend) external onlyOwner {
        require(_backend != deadAddress && _backend != address(0), "_backend account error");
        BACKEND = _backend;
    }

    function buildCopyTraderAccount() external returns (address) {
        require(_CopyAccountList[msg.sender] == address(0), "created already");
        CopyTraderAccount newCopyTraderAccount = new CopyTraderAccount(msg.sender, address(this), gmxVault, gmxRouter, gmxPositionRouter);
        _CopyAccountList[msg.sender] = address(newCopyTraderAccount);
        return address(newCopyTraderAccount);
    }

    function actionPosition(address _user, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDeltaUsd, bool _isLong, uint8 action) external returns (bytes32) {
        require(msg.sender == BACKEND, "msg.send is not backend wallet.");
        require(_user != address(0) && _user != deadAddress, "user address is wrong.");
        address _CopyTraderAccount = _CopyAccountList[_user];
        require(_CopyTraderAccount != address(0), "copy trader account is not created.");
        require(_collateralDelta > 0, "_collateralDelta error");
        require(action < 4, "action error");

        if (action == 0 || action == 1) {
            return ICopyTraderAccount(_CopyTraderAccount).createIncreasePositionETH(_indexToken, _collateralDelta, _sizeDeltaUsd, _isLong);
        } else if (action == 2) {
            return ICopyTraderAccount(_CopyTraderAccount).createDecreasePosition(_indexToken, _collateralDelta, _sizeDeltaUsd, _isLong, false);
        } else if (action == 3) {
            uint256 _sizeUsd; // decimals 30
            uint256 _collateralUsd; // decimals 30
            (_sizeUsd, _collateralUsd, , , , , , ) = IVault(gmxVault).getPosition(_CopyTraderAccount, _collateralToken, _indexToken, _isLong);
            return ICopyTraderAccount(_CopyTraderAccount).createDecreasePosition(_indexToken, _collateralUsd, _sizeUsd, _isLong, true);
        } else {
            return "0x00000";
        }
    }
}

