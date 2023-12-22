// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC721Receiver.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";

import "./IChronosGauge.sol";
import "./IChronosRouter.sol";
import "./IUniPair.sol";
import "./IWETH.sol";

contract StrategyChronos is Ownable, ReentrancyGuard, Pausable, IERC721Receiver {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public gaugeAddress;
    address public wantAddress;
    address public token0Address;
    address public token1Address;
    address public earnedAddress;
    bool public isStable;
    
    address public solidRouterAddress = 0xE708aA9E887980750C040a6A2Cb901c37Aa34f3b;
    address public constant wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant vaultAddress = 0xAdFc4a71444B549Db5324737EFF3B58a4Ef42FF8;
    address public constant feeAddress = 0x7Bff90aa7C618298A3B882858e7f0163b2c43381;
    address public vaultChefAddress;
    address public govAddress;

    uint256 public lastEarnBlock = block.number;
    uint256 public sharesTotal = 0;

    uint256 public controllerFee = 50;
    uint256 public constant feeMaxTotal = 1000;
    uint256 public constant feeMax = 10000;

    uint256 public depositFee = 0; // 1 = 1%
    uint256 public withdrawFeeFactor = 10000;
    uint256 public constant withdrawFeeFactorMax = 10000;
    uint256 public constant withdrawFeeFactorLL = 9900;

    uint256 public slippageFactor = 950;
    uint256 public constant slippageFactorUL = 995;

    IChronosRouter.Route[] public earnedToWethPath;
    IChronosRouter.Route[] public earnedToToken0Path;
    IChronosRouter.Route[] public earnedToToken1Path;
    IChronosRouter.Route[] public wethToToken0Path;
    IChronosRouter.Route[] public wethToToken1Path;
    address[] public rewards;

    constructor(
        address _vaultChef,
        address _gauge,
        address _want,
        address _earned,
        bool _isStable,
        IChronosRouter.Route[] memory _earnedTWethPath,
        IChronosRouter.Route[] memory _earnedTToken0Path,
        IChronosRouter.Route[] memory _earnedTToken1Path,
        IChronosRouter.Route[] memory _wethToTken0Path,
        IChronosRouter.Route[] memory _wethToTken1Path
    ) public {
        govAddress = msg.sender;
        vaultChefAddress = _vaultChef;
        gaugeAddress = _gauge;
        wantAddress = _want;
        earnedAddress = _earned;
        isStable = _isStable;

        rewards.push(_earned);
        token0Address = IUniPair(wantAddress).token0();
        token1Address = IUniPair(wantAddress).token1();

        for(uint i=0; i<_earnedTWethPath.length; i++){
            earnedToWethPath.push();
            earnedToWethPath[i].from = _earnedTWethPath[i].from;
            earnedToWethPath[i].to = _earnedTWethPath[i].to;
            earnedToWethPath[i].stable = _earnedTWethPath[i].stable;
        }

        for(uint i=0; i<_earnedTToken0Path.length; i++){
            earnedToToken0Path.push();
            earnedToToken0Path[i].from = _earnedTToken0Path[i].from;
            earnedToToken0Path[i].to = _earnedTToken0Path[i].to;
            earnedToToken0Path[i].stable = _earnedTToken0Path[i].stable;
        }

        for(uint i=0; i<_earnedTToken1Path.length; i++){
            earnedToToken1Path.push();
            earnedToToken1Path[i].from = _earnedTToken1Path[i].from;
            earnedToToken1Path[i].to = _earnedTToken1Path[i].to;
            earnedToToken1Path[i].stable = _earnedTToken1Path[i].stable;
        }

        for(uint i=0; i<_wethToTken0Path.length; i++){
            wethToToken0Path.push();
            wethToToken0Path[i].from = _wethToTken0Path[i].from;
            wethToToken0Path[i].to = _wethToTken0Path[i].to;
            wethToToken0Path[i].stable = _wethToTken0Path[i].stable;
        }

        for(uint i=0; i<_wethToTken1Path.length; i++){
            wethToToken1Path.push();
            wethToToken1Path[i].from = _wethToTken1Path[i].from;
            wethToToken1Path[i].to = _wethToTken1Path[i].to;
            wethToToken1Path[i].stable = _wethToTken1Path[i].stable;
        }

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

        if(depositFee > 0){
            uint256 feesTaken = _wantAmt.mul(depositFee).div(100);

            IERC20(wantAddress).safeTransfer(vaultAddress, feesTaken);
        }

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
        IChronosGauge(gaugeAddress).depositAll();
        uint256 sharesAfter = vaultSharesTotal();
        
        return sharesAfter.sub(sharesBefore);
    }

    function withdraw(address _userAddress, uint256 _wantAmt) external onlyOwner nonReentrant returns (uint256) {
        require(_wantAmt > 0);
        
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        
        if (_wantAmt > wantAmt) {
            IChronosGauge(gaugeAddress).withdrawAndHarvestAll();
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

        _farm();
        return sharesRemoved;
    }

    function earn() external nonReentrant whenNotPaused {
        IChronosGauge(gaugeAddress).getAllReward();

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
                IChronosRouter(solidRouterAddress).addLiquidity(
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

    function pause() external onlyGov {
        _pause();
    }

    function unpause() external onlyGov {
        _unpause();
        _resetAllowances();
    }
    
    
    function vaultSharesTotal() public view returns (uint256) {
        uint256 balance = IChronosGauge(gaugeAddress).balanceOf(address(this));
        return balance;
    }
    
    function wantLockedTotal() public view returns (uint256) {
        uint256 balance = IChronosGauge(gaugeAddress).balanceOf(address(this));
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
        IChronosGauge(gaugeAddress).withdrawAndHarvestAll();
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

    function setDepositFee(uint256 _depositFee) external onlyGov {
        require(_depositFee <= 10, "Max fee of 10%");
        depositFee = _depositFee;
    }
    
    function _safeSwap(
        uint256 _amountIn,
        IChronosRouter.Route[] memory _path,
        address _to
    ) internal {
        uint256[] memory amounts = IChronosRouter(solidRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];

        IChronosRouter(solidRouterAddress).swapExactTokensForTokens(
            _amountIn,
            amountOut.mul(slippageFactor).div(1000),
            _path,
            _to,
            now.add(600)
        );
    }
    
    function _safeSwapWeth(
        uint256 _amountIn,
        IChronosRouter.Route[] memory _path,
        address _to
    ) internal {
        uint256[] memory amounts = IChronosRouter(solidRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];

        IChronosRouter(solidRouterAddress).swapExactTokensForETH(
            _amountIn,
            amountOut.mul(slippageFactor).div(1000),
            _path,
            _to,
            now.add(600)
        );
    }
    
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
    
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success);
    }

    receive() external payable {}
}
