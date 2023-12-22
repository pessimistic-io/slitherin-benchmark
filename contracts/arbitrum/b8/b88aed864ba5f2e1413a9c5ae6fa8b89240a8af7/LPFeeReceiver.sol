/**
 * https://arcadeum.io
 * https://arcadeum.gitbook.io/arcadeum
 * https://twitter.com/arcadeum_io
 * https://discord.gg/qBbJ2hNPf8
 */

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

import "./ILPFeeReceiver.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IFeeTracker.sol";
import "./IERC20BackwardsCompatible.sol";
import "./IUniswapV2Router02.sol";

contract LPFeeReceiver is ILPFeeReceiver, Ownable, ReentrancyGuard {
    error AlreadyInitialized();
    error OnlyARC(address _caller);
    error NotInitialized();

    address public immutable ARC;
    address public immutable WETH;
    address public immutable USDT;
    IERC20BackwardsCompatible public immutable usdt;
    IUniswapV2Router02 public immutable uniswapV2Router;
    IFeeTracker public sarcFees;
    IFeeTracker public xarcFees;
    IFeeTracker public esarcFees;

    bool private initialized;

    modifier onlyARC() {
        if (msg.sender != ARC) {
            revert OnlyARC(msg.sender);
        }
        _;
    }

    constructor (address _ARC, address _WETH, address _USDT, address _uniswapV2Router, address _sARCFees, address _xARCFees, address _esARCFees) {
        ARC = _ARC;
        WETH = _WETH;
        USDT = _USDT;
        usdt = IERC20BackwardsCompatible(_USDT);
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        sarcFees = IFeeTracker(_sARCFees);
        xarcFees = IFeeTracker(_xARCFees);
        esarcFees = IFeeTracker(_esARCFees);
    }

    function initialize() external nonReentrant onlyOwner {
        if (initialized) {
            revert AlreadyInitialized();
        }

        usdt.approve(address(sarcFees), type(uint256).max);
        usdt.approve(address(xarcFees), type(uint256).max);
        usdt.approve(address(esarcFees), type(uint256).max);

        initialized = true;
    }

    function depositYield() external payable nonReentrant onlyARC {
        if (!initialized) {
            revert NotInitialized();
        }

        address[] memory _path = new address[](2);
        _path[0] = WETH;
        _path[1] = USDT;
        uniswapV2Router.swapExactETHForTokens{value: msg.value}(0, _path, address(this), block.timestamp);
        _payYield(usdt.balanceOf(address(this)));
    }

    function _payYield(uint256 _fee) private {
        xarcFees.depositYield(2, _fee * 7000 / 10000);
        uint256 _fee15Pct = _fee * 1500 / 10000;
        sarcFees.depositYield(2, _fee15Pct);
        esarcFees.depositYield(2, _fee15Pct);
    }
}

