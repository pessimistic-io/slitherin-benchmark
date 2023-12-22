// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";

import "./IGHALend.sol";
import "./ISwapRouter.sol";
import "./IWETH.sol";

contract StrategyGHALend is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint24 public poolFee;
    address public ghaLendAddress;
    address public wantAddress;
    address public earnedAddress;
    uint256 private decimalAdj; // Decimal handling for different tokens decimals
    
    address public constant esGHAAddress = 0x3129F42a1b574715921cb65FAbB0F0f9bd8b4f39;
    address public uniRouterAddress = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant vaultAddress = 0xAdFc4a71444B549Db5324737EFF3B58a4Ef42FF8;
    address public constant feeAddress = 0x7Bff90aa7C618298A3B882858e7f0163b2c43381;
    address public vaultChefAddress;
    address public govAddress;

    uint256 public lastEarnBlock = block.number;
    uint256 public sharesTotal = 0;

    uint256 public controllerFee = 1000;
    uint256 public constant feeMaxTotal = 1000;
    uint256 public constant feeMax = 10000;

    uint256 public depositFee = 0; // 1 = 1%
    uint256 public withdrawFeeFactor = 10000;
    uint256 public constant withdrawFeeFactorMax = 10000;
    uint256 public constant withdrawFeeFactorLL = 9900;

    uint256 public slippageFactor = 950;
    uint256 public constant slippageFactorUL = 995;

    constructor(
        address _vaultChef,
        address _want,
        address _earned,
        address _ghaLendAddress,
        uint24 _poolFee,
        uint256 _decimalGap
    ) public {
        govAddress = msg.sender;
        vaultChefAddress = _vaultChef;
        ghaLendAddress = _ghaLendAddress;

        wantAddress = _want;
        earnedAddress = _earned;
        poolFee = _poolFee;
        decimalAdj = 10 ** _decimalGap;

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
        IGHALend(ghaLendAddress).deposit(wantAmt);
        uint256 sharesAfter = vaultSharesTotal();
        
        return sharesAfter.sub(sharesBefore);
    }

    function withdraw(address _userAddress, uint256 _wantAmt) external onlyOwner nonReentrant returns (uint256) {
        require(_wantAmt > 0);
        
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        
        if (_wantAmt > wantAmt) {
            IGHALend(ghaLendAddress).withdraw(_wantAmt.sub(wantAmt));
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
        IGHALend(ghaLendAddress).getReward();

        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        if (earnedAmt > 0) {
            earnedAmt = distributeFees(earnedAmt, earnedAddress);

            // Swap to want
            _safeSwap(
                earnedAddress,
                wantAddress,
                poolFee,
                earnedAmt,
                address(this)
            );

            // Burn esGHA tokens to dead address
            uint256 esGHAEarnedAmt = IERC20(esGHAAddress).balanceOf(address(this));
            if(esGHAEarnedAmt > 0){
                IERC20(esGHAAddress).safeTransfer(0x000000000000000000000000000000000000dEaD, esGHAEarnedAmt);
            }
        }
        lastEarnBlock = block.number;
        
        _farm();
    }

    function distributeFees(uint256 _earnedAmt, address _earnedAddress) internal returns (uint256) {
        if (controllerFee > 0) {
            uint256 fee = _earnedAmt.mul(controllerFee).div(feeMax);
            
            if (_earnedAddress == wethAddress) {
                IWETH(wethAddress).withdraw(fee);
                safeTransferETH(feeAddress, fee);
            } else {
            // Swap to want
                _safeSwap(
                    earnedAddress,
                    wethAddress,
                    poolFee,
                    fee,
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
        uint256 balance = IGHALend(ghaLendAddress).xdeposits(address(this));
        if(decimalAdj != 0){
            balance = balance.div(decimalAdj);
        }
        return balance;
    }
    
    function wantLockedTotal() public view returns (uint256) {
        uint256 balance = IGHALend(ghaLendAddress).xdeposits(address(this));
        if(decimalAdj != 0){
            balance = balance.div(decimalAdj);
        }
        return IERC20(wantAddress).balanceOf(address(this)).add(balance);
    }

    function _resetAllowances() internal {
        
        IERC20(wantAddress).safeApprove(ghaLendAddress, uint256(0));
        IERC20(wantAddress).safeIncreaseAllowance(
            ghaLendAddress,
            uint256(-1)
        );

        IERC20(earnedAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            uint256(-1)
        );

        IERC20(wethAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(wethAddress).safeIncreaseAllowance(
            uniRouterAddress,
            uint256(-1)
        );
        
        IERC20(wantAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(wantAddress).safeIncreaseAllowance(
            uniRouterAddress,
            uint256(-1)
        );
    }

    function resetAllowances() external onlyGov {
        _resetAllowances();
    }

    function panic() external onlyGov {
        _pause();
        uint256 balance = IGHALend(ghaLendAddress).xdeposits(address(this));
        IGHALend(ghaLendAddress).withdraw(balance);
    }

    function unpanic() external onlyGov {
        _unpause();
        _farm();
    }
    
    function setSettings(
        uint256 _controllerFee,
        uint256 _withdrawFeeFactor,
        uint256 _slippageFactor,
        address _uniRouterAddress
    ) external onlyGov {
        require(_controllerFee <= feeMaxTotal);
        require(_withdrawFeeFactor >= withdrawFeeFactorLL);
        require(_withdrawFeeFactor <= withdrawFeeFactorMax);
        require(_slippageFactor <= slippageFactorUL);
        controllerFee = _controllerFee;
        withdrawFeeFactor = _withdrawFeeFactor;
        slippageFactor = _slippageFactor;
        uniRouterAddress = _uniRouterAddress;
    }

    function setGov(address _govAddress) external onlyGov {
        govAddress = _govAddress;
    }

    function setDepositFee(uint256 _depositFee) external onlyGov {
        require(_depositFee <= 10, "Max fee of 10%");
        depositFee = _depositFee;
    }
    
    function _safeSwap(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint amountIn,
        address to
    ) internal {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: to,
                deadline: now.add(600),
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        uint256 amountOut = ISwapRouter(uniRouterAddress).exactInputSingle(params);
    }
    
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success);
    }

    receive() external payable {}
}
