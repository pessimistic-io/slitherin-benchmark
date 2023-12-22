// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./Address.sol";
import "./IERC20.sol";

import {ICopyTraderIndex, IVault, IRouter, IPositionRouter} from "./gmxInterfaces.sol";

contract CopyTraderAccount {
    using Address for address;

    /* ========== CONSTANTS ========== */
    address private constant _usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address private constant _wbtc = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address private constant _weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address private constant _uni = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0;
    address private constant _link = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;

    address public gmxVault = address(0);
    address public gmxRouter = address(0);
    address public gmxPositionRouter = address(0);

    bytes32 private constant _referralCode = 0x0000000000000000000000000000000000000000000000000000000000000000;
    address private constant _callbackTarget = 0x0000000000000000000000000000000000000000;

    /* ========== STATE VARIABLES ========== */
    address public owner;
    address public copyTraderIndex = address(0);
    bool public isCopyTrading = false;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _owner, address _copyTraderIndex, address _gmxVault, address _gmxRouter, address _gmxPositionRouter) {
        owner = _owner;
        copyTraderIndex = _copyTraderIndex;
        gmxVault = _gmxVault;
        gmxRouter = _gmxRouter;
        gmxPositionRouter = _gmxPositionRouter;
        IRouter(gmxRouter).approvePlugin(gmxPositionRouter);
    }

    receive() external payable {}

    /* ========== Modifier ========== */
    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /* ========== VIEWS ========== */
    function balanceOfEth() public view returns (uint256) {
        return address(this).balance;
    }

    function balanceOfToken(address _tokenAddr) public view returns (uint256) {
        return IERC20(_tokenAddr).balanceOf(address(this));
    }

    function _validateIndexToken(address _indexToken) private pure returns (bool) {
        return _indexToken == _wbtc || _indexToken == _weth || _indexToken == _uni || _indexToken == _link;
    }

    function _getCollateralInUsd(address _tokenAddr, address _indexToken, bool _isLong) private view returns (uint256) {
        uint256 _currentCollateralUsd; // decimals 30
        (, _currentCollateralUsd, , , , , , ) = IVault(gmxVault).getPosition(address(this), _tokenAddr, _indexToken, _isLong);
        return _currentCollateralUsd;
    }

    function _getTokenPrice(address _indexToken, bool _isLong) private view returns (uint256) {
        uint256 _minTokenPrice = IVault(gmxVault).getMinPrice(_indexToken); // decimals 30
        uint256 _maxTokenPrice = IVault(gmxVault).getMaxPrice(_indexToken); // decimals 30
        return _isLong ? _minTokenPrice : _maxTokenPrice; // decimals 30
    }

    function _getAcceptableTokenPrice(bool is_increase, address _indexToken, bool _isLong) private view returns (uint256) {
        uint256 indexTokenPrice = _getTokenPrice(_indexToken, _isLong); // decimals 30
        uint256 offset_indexTokenPrice = (indexTokenPrice * 2) / 100; //  2 %  // decimals 30
        if (is_increase) {
            return _isLong ? indexTokenPrice + offset_indexTokenPrice : indexTokenPrice - offset_indexTokenPrice; // decimals 30
        } else {
            return _isLong ? indexTokenPrice - offset_indexTokenPrice : indexTokenPrice + offset_indexTokenPrice; // decimals 30
        }
    }

    function _getNewCollateralInUsd(uint256 _amountInEth, address _collateralToken, address _indexToken, bool _isLong) private view returns (uint256) {
        uint256 currentCollateralUsd = _getCollateralInUsd(_collateralToken, _indexToken, _isLong); // decimals 30
        uint256 priceEth = _getTokenPrice(_weth, _isLong); // decimals 30
        uint256 addedCollateralUsd = (_amountInEth * priceEth) / 1e18; // decimals 30
        return currentCollateralUsd + addedCollateralUsd; // decimals 30
    }

    function _getGmxMinExecutionFee() private view returns (uint256) {
        return IPositionRouter(gmxPositionRouter).minExecutionFee(); //decimals 18
    }

    function _getGmxExecutionFee() private view returns (uint256) {
        uint256 _minExecutionFee = _getGmxMinExecutionFee();
        return (_minExecutionFee * 120) / 100; // decimals 18	1.2 x minExecutionFee
    }

    function _getMinCollateralUsd() private view returns (uint256) {
        return ICopyTraderIndex(copyTraderIndex).MIN_COLLATERAL_USD(); //decimals 30
    }

    function _getCopyTraderFee() private view returns (uint256) {
        return ICopyTraderIndex(copyTraderIndex).COPY_TRADER_FEE(); //decimals 2
    }

    function _getCtExecuteFee() private view returns (uint256) {
        return ICopyTraderIndex(copyTraderIndex).CT_EXECUTE_FEE(); //decimals 18
    }

    function _getTreasury() private view returns (address) {
        return ICopyTraderIndex(copyTraderIndex).TREASURY();
    }

    function _getBackend() private view returns (address) {
        return ICopyTraderIndex(copyTraderIndex).BACKEND();
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function startCopyTrading() external onlyOwner {
        require(!isCopyTrading, "started already");
        isCopyTrading = true;
    }

    function stopCopyTrading() external onlyOwner {
        require(isCopyTrading, "stopped already");
        isCopyTrading = false;
    }

    function withdrawETH(uint256 _amount) external onlyOwner {
        require(!isCopyTrading, "copy trading...");
        require(_amount > 0, "must be greater than zero");
        require(_amount <= balanceOfEth(), "must be less than balance of contract");
        payable(owner).transfer(_amount);
    }

    function withdrawToken(address _tokenAddr, uint256 _amount) external onlyOwner {
        require(!isCopyTrading, "copy trading...");
        require(_amount > 0, "must be greater than zero");
        require(_amount <= balanceOfToken(_tokenAddr), "must be less than balance of contract");
        IERC20(_tokenAddr).transfer(owner, _amount);
    }

    function createIncreasePositionETH(address collateralToken, address indexToken, uint256 amountInEth, uint256 sizeDeltaUsd, bool isLong) external returns (bytes32) {
        if (isCopyTrading) {
            require(copyTraderIndex == msg.sender, "sender is not copy trader index");
        } else {
            require(owner == msg.sender, "sender is not owner");
        }
        require(_validateIndexToken(indexToken), "invalid token."); // weth, wbtc, uni, link
        require(amountInEth > 0, "amountIn must be greater than zero"); // decimals 18
        require(_getNewCollateralInUsd(amountInEth, collateralToken, indexToken, isLong) >= _getMinCollateralUsd(), "amountIn must be greater than minColateralUsd.");

        uint256 gmxExecutionFee = _getGmxExecutionFee(); // decimals 18

        // Calc AmountIn of Eth
        uint256 incAmountInEth = 0; // decimals 18
        if (isCopyTrading) {
            uint256 feeAmountEth = (amountInEth * _getCopyTraderFee()) / 10000; // decimals 18
            uint256 executeFeeEth = _getCtExecuteFee(); // decimals 18
            incAmountInEth = amountInEth - feeAmountEth + gmxExecutionFee; // decimals 18
            require(incAmountInEth + executeFeeEth <= balanceOfEth(), "insufficient funds in copy trader account");
            payable(_getTreasury()).transfer(feeAmountEth);
            payable(_getBackend()).transfer(executeFeeEth);
        } else {
            incAmountInEth = amountInEth + gmxExecutionFee; // decimals 18
            require(incAmountInEth <= balanceOfEth(), "insufficient funds in copy trader account");
        }

        //Calc acceptablePrice
        uint256 acceptableIndexTokenPrice = _getAcceptableTokenPrice(true, indexToken, isLong); // decimals 30

        // execute increase Position
        bytes32 returnValue;
        if (isLong) {
            if (indexToken == _weth) {
                address[] memory path = new address[](1);
                path[0] = _weth;
                returnValue = IPositionRouter(gmxPositionRouter).createIncreasePositionETH{value: incAmountInEth}(path, indexToken, 0, sizeDeltaUsd, isLong, acceptableIndexTokenPrice, gmxExecutionFee, _referralCode, _callbackTarget);
            } else {
                address[] memory path = new address[](2);
                path[0] = _weth;
                path[1] = indexToken;
                returnValue = IPositionRouter(gmxPositionRouter).createIncreasePositionETH{value: incAmountInEth}(path, indexToken, 0, sizeDeltaUsd, isLong, acceptableIndexTokenPrice, gmxExecutionFee, _referralCode, _callbackTarget);
            }
        } else {
            address[] memory path = new address[](2);
            path[0] = _weth;
            path[1] = _usdc;
            returnValue = IPositionRouter(gmxPositionRouter).createIncreasePositionETH{value: incAmountInEth}(path, indexToken, 0, sizeDeltaUsd, isLong, acceptableIndexTokenPrice, gmxExecutionFee, _referralCode, _callbackTarget);
        }
        return returnValue;
    }

    function createDecreasePosition(address collateralToken, address indexToken, uint256 collateralDeltaUsd, uint256 sizeDeltaUsd, bool isLong, bool _isClose) external returns (bytes32) {
        if (isCopyTrading) {
            require(copyTraderIndex == msg.sender, "sender is not copy trader index");
        } else {
            require(owner == msg.sender, "sender is not owner");
        }
        require(_validateIndexToken(indexToken), "invalid token."); // weth, wbtc, uni, link
        // require(collateralDeltaUsd > 0, "collateralDeltaUsd must be greater than zero"); // decimals 18
        if (!_isClose) {
            uint256 currentCollateralUsd = _getCollateralInUsd(collateralToken, indexToken, isLong); // decimals 30
            require(currentCollateralUsd - collateralDeltaUsd >= _getMinCollateralUsd(), "new CollateralUsd must be greater than minColateralUsd.");
        }

        uint256 gmxExecutionFee = _getGmxExecutionFee(); // decimals 18

        //Calc acceptablePrice
        uint256 acceptableIndexTokenPrice = _getAcceptableTokenPrice(false, indexToken, isLong); // decimals 30

        // execute decrease Position
        bytes32 returnValue;
        if (isLong) {
            if (indexToken == _weth) {
                address[] memory path = new address[](1);
                path[0] = _weth;
                returnValue = IPositionRouter(gmxPositionRouter).createDecreasePosition{value: gmxExecutionFee}(path, indexToken, collateralDeltaUsd, sizeDeltaUsd, isLong, address(this), acceptableIndexTokenPrice, 0, gmxExecutionFee, true, _callbackTarget);
            } else {
                address[] memory path = new address[](2);
                path[0] = indexToken;
                path[1] = _weth;
                returnValue = IPositionRouter(gmxPositionRouter).createDecreasePosition{value: gmxExecutionFee}(path, indexToken, collateralDeltaUsd, sizeDeltaUsd, isLong, address(this), acceptableIndexTokenPrice, 0, gmxExecutionFee, true, _callbackTarget);
            }
        } else {
            address[] memory path = new address[](2);
            path[0] = _usdc;
            path[1] = _weth;
            returnValue = IPositionRouter(gmxPositionRouter).createDecreasePosition{value: gmxExecutionFee}(path, indexToken, collateralDeltaUsd, sizeDeltaUsd, isLong, address(this), acceptableIndexTokenPrice, 0, gmxExecutionFee, true, _callbackTarget);
        }

        // Calc fee of Eth
        if (isCopyTrading) {
            uint256 priceEth = _getTokenPrice(_weth, isLong); // decimals 30
            uint256 feeAmountUsd = (collateralDeltaUsd * _getCopyTraderFee()) / 10000; // decimals 30
            uint256 feeAmountEth = (feeAmountUsd * 1e18) / priceEth; // decimals 18
            payable(_getTreasury()).transfer(feeAmountEth);
            payable(_getBackend()).transfer(_getCtExecuteFee());
        }

        return returnValue;
    }
}

