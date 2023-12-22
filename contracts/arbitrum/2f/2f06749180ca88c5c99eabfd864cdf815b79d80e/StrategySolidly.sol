// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";

import "./IGauge.sol";
import "./ISRouter.sol";
import "./IUniPair.sol";
import "./IWETH.sol";

contract StrategySolidly is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public gaugeAddress;
    address public wantAddress;
    address public token0Address;
    address public token1Address;
    address public earnedAddress;
    bool public isStable;
    
    address public solidRouterAddress = 0xF26515D5482e2C2FD237149bF6A653dA4794b3D0;
    address public constant wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant vaultAddress = 0xCD7bA0668a8F528AcA61aBa766F681E598a4673b;
    address public constant feeAddress = 0xCD7bA0668a8F528AcA61aBa766F681E598a4673b;
    address public vaultChefAddress;
    address public govAddress;

    uint256 public lastEarnBlock = block.number;
    uint256 public sharesTotal = 0;

    uint256 public controllerFee = 50;
    uint256 public constant feeMaxTotal = 1000;
    uint256 public constant feeMax = 10000;

    uint256 public withdrawFeeFactor = 10000;
    uint256 public constant withdrawFeeFactorMax = 10000;
    uint256 public constant withdrawFeeFactorLL = 9900;

    uint256 public slippageFactor = 950;
    uint256 public constant slippageFactorUL = 995;

    ISRouter.Route[] public earnedToWethPath;
    ISRouter.Route[] public earnedToToken0Path;
    ISRouter.Route[] public earnedToToken1Path;
    ISRouter.Route[] public wethToToken0Path;
    ISRouter.Route[] public wethToToken1Path;
    ISRouter.Route[] public token0ToEarnedPath;
    ISRouter.Route[] public token1ToEarnedPath;
    address[] public rewards;

    constructor(
        address _vaultChefAddress,
        address _gaugeAddress,
        bool _isStable,
        address _wantAddress,
        address _earnedAddress
    ) public {
        govAddress = msg.sender;
        vaultChefAddress = _vaultChefAddress;

        gaugeAddress = _gaugeAddress;
        isStable = _isStable;
        wantAddress = _wantAddress;
        rewards.push(_earnedAddress);
        token0Address = IUniPair(wantAddress).token0();
        token1Address = IUniPair(wantAddress).token1();

        earnedAddress = _earnedAddress;

        earnedToWethPath.push();
        earnedToWethPath[0].from = _earnedAddress;
        earnedToWethPath[0].to = wethAddress;
        earnedToWethPath[0].stable = _isStable;

        earnedToToken0Path.push();
        earnedToToken0Path[0].from = earnedAddress;
        earnedToToken0Path[0].to = token0Address;
        earnedToToken0Path[0].stable = isStable;

        earnedToToken1Path.push();
        earnedToToken1Path[0].from = earnedAddress;
        earnedToToken1Path[0].to = token1Address;
        earnedToToken1Path[0].stable = isStable;

        wethToToken0Path.push();
        wethToToken0Path[0].from = wethAddress;
        wethToToken0Path[0].to = token0Address;
        wethToToken0Path[0].stable = isStable;

        wethToToken1Path.push();
        wethToToken1Path[0].from = wethAddress;
        wethToToken1Path[0].to = token1Address;
        wethToToken1Path[0].stable = isStable;

        token0ToEarnedPath.push();
        token0ToEarnedPath[0].from = token0Address;
        token0ToEarnedPath[0].to = earnedAddress;
        token0ToEarnedPath[0].stable = isStable;

        token1ToEarnedPath.push();
        token1ToEarnedPath[0].from = token1Address;
        token1ToEarnedPath[0].to = earnedAddress;
        token1ToEarnedPath[0].stable = isStable;

        transferOwnership(vaultChefAddress);
        _resetAllowances();
    }
    
    modifier onlyGov() {
        require(msg.sender == govAddress);
        _;
    }
    
    function deposit(address _userAddress, uint256 _wantAmt) external onlyOwner nonReentrant whenNotPaused returns (uint256) {
        uint256 wantLockedBefore = wantLockedTotal();

        IERC20(wantAddress).safeTransferFrom(
            address(msg.sender),
            address(this),
            _wantAmt
        );

        uint256 sharesAdded = _farm();
        if (sharesTotal > 0) {
            sharesAdded = sharesAdded.mul(sharesTotal).div(wantLockedBefore);
        }
        sharesTotal = sharesTotal.add(sharesAdded);

        return sharesAdded;
    }

    function _farm() internal returns (uint256) {
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        if (wantAmt == 0) return 0;
        
        uint256 sharesBefore = vaultSharesTotal();
        IGauge(gaugeAddress).depositAll(0);
        uint256 sharesAfter = vaultSharesTotal();
        
        return sharesAfter.sub(sharesBefore);
    }

    function withdraw(address _userAddress, uint256 _wantAmt) external onlyOwner nonReentrant returns (uint256) {
        require(_wantAmt > 0);
        
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        
        if (_wantAmt > wantAmt) {
            IGauge(gaugeAddress).withdraw(_wantAmt.sub(wantAmt));
            wantAmt = IERC20(wantAddress).balanceOf(address(this));
        }

        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }

        if (_wantAmt > wantLockedTotal()) {
            _wantAmt = wantLockedTotal();
        }

        uint256 sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal());
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        sharesTotal = sharesTotal.sub(sharesRemoved);
        
        uint256 withdrawFee = _wantAmt
            .mul(withdrawFeeFactorMax.sub(withdrawFeeFactor))
            .div(withdrawFeeFactorMax);
        IERC20(wantAddress).safeTransfer(vaultAddress, withdrawFee);
        
        _wantAmt = _wantAmt.sub(withdrawFee);

        IERC20(wantAddress).safeTransfer(vaultChefAddress, _wantAmt);

        return sharesRemoved;
    }

    function earn() external nonReentrant whenNotPaused {
        IGauge(gaugeAddress).getReward(address(this), rewards);

        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
        uint256 wethAmt = IERC20(wethAddress).balanceOf(address(this));

        if (earnedAmt > 0) {
            earnedAmt = distributeFees(earnedAmt, earnedAddress);
    
            if (earnedAddress != token0Address) {
                _safeSwap(
                    earnedAmt.div(2),
                    earnedToToken0Path,
                    address(this)
                );
            }
    
            if (earnedAddress != token1Address) {
                _safeSwap(
                    earnedAmt.div(2),
                    earnedToToken1Path,
                    address(this)
                );
            }
        }
        
        if (wethAmt > 0) {
            wethAmt = distributeFees(wethAmt, wethAddress);
    
            if (wethAddress != token0Address) {
                _safeSwap(
                    wethAmt.div(2),
                    wethToToken0Path,
                    address(this)
                );
            }
    
            if (wethAddress != token1Address) {
                _safeSwap(
                    wethAmt.div(2),
                    wethToToken1Path,
                    address(this)
                );
            }
        }
        
        if (earnedAmt > 0 || wethAmt > 0) {
            uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
            uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
            if (token0Amt > 0 && token1Amt > 0) {
                ISRouter(solidRouterAddress).addLiquidity(
                    token0Address,
                    token1Address,
                    isStable,
                    token0Amt,
                    token1Amt,
                    0,
                    0,
                    address(this),
                    now.add(600)
                );
            }

            lastEarnBlock = block.number;
    
            _farm();
        }
    }

    function distributeFees(uint256 _earnedAmt, address _earnedAddress) internal returns (uint256) {
        if (controllerFee > 0) {
            uint256 fee = _earnedAmt.mul(controllerFee).div(feeMax);
            
            if (_earnedAddress == wethAddress) {
                IWETH(wethAddress).withdraw(fee);
                safeTransferETH(feeAddress, fee);
            } else {
                _safeSwapWeth(
                    fee,
                    earnedToWethPath,
                    feeAddress
                );
            }
            
            _earnedAmt = _earnedAmt.sub(fee);
        }

        return _earnedAmt;
    }

    function convertDustToEarned() external nonReentrant whenNotPaused {

        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Amt > 0 && token0Address != earnedAddress) {
            _safeSwap(
                token0Amt,
                token0ToEarnedPath,
                address(this)
            );
        }

        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Amt > 0 && token1Address != earnedAddress) {
            _safeSwap(
                token1Amt,
                token1ToEarnedPath,
                address(this)
            );
        }
    }

    function pause() external onlyGov {
        _pause();
    }

    function unpause() external onlyGov {
        _unpause();
        _resetAllowances();
    }
    
    
    function vaultSharesTotal() public view returns (uint256) {
        uint256 balance = IGauge(gaugeAddress).balanceOf(address(this));
        return balance;
    }
    
    function wantLockedTotal() public view returns (uint256) {
        uint256 balance = IGauge(gaugeAddress).balanceOf(address(this));
        return IERC20(wantAddress).balanceOf(address(this)).add(balance);
    }

    function _resetAllowances() internal {
        
        IERC20(wantAddress).safeApprove(gaugeAddress, uint256(0));
        IERC20(wantAddress).safeIncreaseAllowance(
            gaugeAddress,
            uint256(-1)
        );

        IERC20(earnedAddress).safeApprove(solidRouterAddress, uint256(0));
        IERC20(earnedAddress).safeIncreaseAllowance(
            solidRouterAddress,
            uint256(-1)
        );

        IERC20(wethAddress).safeApprove(solidRouterAddress, uint256(0));
        IERC20(wethAddress).safeIncreaseAllowance(
            solidRouterAddress,
            uint256(-1)
        );
        
        IERC20(wantAddress).safeApprove(solidRouterAddress, uint256(0));
        IERC20(wantAddress).safeIncreaseAllowance(
            solidRouterAddress,
            uint256(-1)
        );

        IERC20(token0Address).safeApprove(solidRouterAddress, uint256(0));
        IERC20(token0Address).safeIncreaseAllowance(
            solidRouterAddress,
            uint256(-1)
        );

        IERC20(token1Address).safeApprove(solidRouterAddress, uint256(0));
        IERC20(token1Address).safeIncreaseAllowance(
            solidRouterAddress,
            uint256(-1)
        );
    }

    function resetAllowances() external onlyGov {
        _resetAllowances();
    }

    function panic() external onlyGov {
        _pause();
        IGauge(gaugeAddress).withdrawAll();
    }

    function unpanic() external onlyGov {
        _unpause();
        _farm();
    }
    
    function setSettings(
        uint256 _controllerFee,
        uint256 _withdrawFeeFactor,
        uint256 _slippageFactor,
        address _solidRouterAddress
    ) external onlyGov {
        require(_controllerFee <= feeMaxTotal);
        require(_withdrawFeeFactor >= withdrawFeeFactorLL);
        require(_withdrawFeeFactor <= withdrawFeeFactorMax);
        require(_slippageFactor <= slippageFactorUL);
        controllerFee = _controllerFee;
        withdrawFeeFactor = _withdrawFeeFactor;
        slippageFactor = _slippageFactor;
        solidRouterAddress = _solidRouterAddress;
    }

    function setGov(address _govAddress) external onlyGov {
        govAddress = _govAddress;
    }
    
    function _safeSwap(
        uint256 _amountIn,
        ISRouter.Route[] memory _path,
        address _to
    ) internal {
        uint256[] memory amounts = ISRouter(solidRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];

        ISRouter(solidRouterAddress).swapExactTokensForTokens(
            _amountIn,
            amountOut.mul(slippageFactor).div(1000),
            _path,
            _to,
            now.add(600)
        );
    }
    
    function _safeSwapWeth(
        uint256 _amountIn,
        ISRouter.Route[] memory _path,
        address _to
    ) internal {
        uint256[] memory amounts = ISRouter(solidRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];

        ISRouter(solidRouterAddress).swapExactTokensForMATIC(
            _amountIn,
            amountOut.mul(slippageFactor).div(1000),
            _path,
            _to,
            now.add(600)
        );
    }
    
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success);
    }

    receive() external payable {}
}
