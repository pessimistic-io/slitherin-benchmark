// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";

import "./IWombatMasterchef.sol";
import "./ICamelotRouter.sol";
import "./IWombatRouter.sol";
import "./IWombatPool.sol";

contract StrategyWombat is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public vaultChefAddress;
    address public masterchefAddress;
    uint256 public pid;
    address public wantAddress;
    address public assetAddress;
    address public earnedAddress;
    
    address public uniRouterAddress;
    address public wombatRouterAddress;
    address public wombatPoolAddress;
    address public usdtAddress = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address public constant vaultAddress = 0xAdFc4a71444B549Db5324737EFF3B58a4Ef42FF8;
    address public constant feeAddress = 0x7Bff90aa7C618298A3B882858e7f0163b2c43381;
    address public govAddress;

    uint256 public lastEarnBlock = block.number;
    uint256 public sharesTotal = 0;

    uint256 public controllerFee = 50;
    uint256 public constant feeMaxTotal = 1000;
    uint256 public constant feeMax = 10000; // 100 = 1%

    uint256 public depositFee = 0; // 1 = 1%
    uint256 public withdrawFeeFactor = 10000; // 0% withdraw fee
    uint256 public constant withdrawFeeFactorMax = 10000;
    uint256 public constant withdrawFeeFactorLL = 9900;

    uint256 public slippageFactor = 950; // 5% default slippage tolerance
    uint256 public constant slippageFactorUL = 995;

    address[] public earnedToUsdtPath;
    address[] public usdtToStablePath;
    address[] public poolPath;

    constructor(
        address _vaultChef,
        address _masterchef,
        address _wombatPool,
        uint256 _pid,
        address _uniRouter,
        address _wombatRouter,
        address _want,
        address _asset,
        address _earned
    ) public {
        govAddress = msg.sender;
        vaultChefAddress = _vaultChef;
        masterchefAddress = _masterchef;
        uniRouterAddress = _uniRouter;
        wombatRouterAddress = _wombatRouter;
        wombatPoolAddress = _wombatPool;

        wantAddress = _want;
        assetAddress = _asset;
        earnedAddress = _earned;
        pid = _pid;

        earnedToUsdtPath = [earnedAddress, usdtAddress];
        usdtToStablePath = [usdtAddress, assetAddress];
        poolPath = [wombatPoolAddress];

        transferOwnership(vaultChefAddress);
        
        _resetAllowances();
    }
    
    event SetSettings(
        uint256 _controllerFee,
        uint256 _withdrawFeeFactor,
        uint256 _slippageFactor,
        address _uniRouterAddress
    );
    
    modifier onlyGov() {
        require(msg.sender == govAddress, "!gov");
        _;
    }
    
    function deposit(address _userAddress, uint256 _wantAmt) external onlyOwner nonReentrant whenNotPaused returns (uint256) {
        // Call must happen before transfer
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

        // Proper deposit amount for tokens with fees, or vaults with deposit fees
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
        IWombatMasterchef(masterchefAddress).deposit(pid, wantAmt);
        uint256 sharesAfter = vaultSharesTotal();
        
        return sharesAfter.sub(sharesBefore);
    }

    function withdraw(address _userAddress, uint256 _wantAmt) external onlyOwner nonReentrant returns (uint256) {
        require(_wantAmt > 0, "_wantAmt is 0");
        
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantAmt) {
            IWombatMasterchef(masterchefAddress).withdraw(pid, _wantAmt.sub(wantAmt));
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
        
        // Withdraw fee
        uint256 withdrawFee = _wantAmt
            .mul(withdrawFeeFactorMax.sub(withdrawFeeFactor))
            .div(withdrawFeeFactorMax);
        IERC20(wantAddress).safeTransfer(vaultAddress, withdrawFee);
        
        _wantAmt = _wantAmt.sub(withdrawFee);

        IERC20(wantAddress).safeTransfer(vaultChefAddress, _wantAmt);

        return sharesRemoved;
    }

    function earn() external nonReentrant whenNotPaused {
        // Harvest farm tokens
        uint256 amountToWithdraw = vaultSharesTotal();
        IWombatMasterchef(masterchefAddress).withdraw(pid, amountToWithdraw);

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        if (earnedAmt > 0) {
            earnedAmt = distributeFees(earnedAmt);
    
            // Swap to USDT
            _safeSwap(
                earnedAmt,
                earnedToUsdtPath,
                address(this)
            );
    
            uint256 usdtAmount = IERC20(usdtAddress).balanceOf(address(this));
            if (usdtAmount > 0 && assetAddress != usdtAddress) {
                // Swap to asset
                _safeSwapToAsset(
                    usdtAmount,
                    usdtToStablePath,
                    address(this)
                );
            }
    
            // Get want tokens, ie. add liquidity
            uint256 assetAmount = IERC20(assetAddress).balanceOf(address(this));
            if (assetAmount > 0) {
                IWombatPool(wombatPoolAddress).deposit(
                    assetAddress,
                    assetAmount,
                    0,
                    address(this),
                    now.add(600),
                    false
                );
            }
    
            lastEarnBlock = block.number;
    
            _farm();
        }
    }

    // To pay for earn function
    function distributeFees(uint256 _earnedAmt) internal returns (uint256) {
        if (controllerFee > 0) {
            uint256 fee = _earnedAmt.mul(controllerFee).div(feeMax);
            _safeSwap(
                fee,
                earnedToUsdtPath,
                feeAddress
            );
            
            _earnedAmt = _earnedAmt.sub(fee);
        }

        return _earnedAmt;
    }

    // Emergency!!
    function pause() external onlyGov {
        _pause();
    }

    // False alarm
    function unpause() external onlyGov {
        _unpause();
        _resetAllowances();
    }
    
    
    function vaultSharesTotal() public view returns (uint256) {
        (uint256 amount,) = IWombatMasterchef(masterchefAddress).userInfo(pid, address(this));
        return amount;
    }
    
    function wantLockedTotal() public view returns (uint256) {
        return IERC20(wantAddress).balanceOf(address(this))
            .add(vaultSharesTotal());
    }

    function _resetAllowances() internal {
        
        IERC20(wantAddress).safeApprove(masterchefAddress, uint256(0));
        IERC20(wantAddress).safeIncreaseAllowance(
            masterchefAddress,
            uint256(-1)
        );

        IERC20(earnedAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            uint256(-1)
        );
        
        IERC20(wantAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(wantAddress).safeIncreaseAllowance(
            uniRouterAddress,
            uint256(-1)
        );

        IERC20(usdtAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(usdtAddress).safeIncreaseAllowance(
            uniRouterAddress,
            uint256(-1)
        );

        IERC20(usdtAddress).safeApprove(wombatRouterAddress, uint256(0));
        IERC20(usdtAddress).safeIncreaseAllowance(
            wombatRouterAddress,
            uint256(-1)
        );

        IERC20(assetAddress).safeApprove(wombatPoolAddress, uint256(0));
        IERC20(assetAddress).safeIncreaseAllowance(
            wombatPoolAddress,
            uint256(-1)
        );
    }

    function resetAllowances() external onlyGov {
        _resetAllowances();
    }

    function panic() external onlyGov {
        _pause();
        IWombatMasterchef(masterchefAddress).emergencyWithdraw(pid);
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
        require(_controllerFee <= feeMaxTotal, "Max fee of 10%");
        require(_withdrawFeeFactor >= withdrawFeeFactorLL, "_withdrawFeeFactor too low");
        require(_withdrawFeeFactor <= withdrawFeeFactorMax, "_withdrawFeeFactor too high");
        require(_slippageFactor <= slippageFactorUL, "_slippageFactor too high");
        controllerFee = _controllerFee;
        withdrawFeeFactor = _withdrawFeeFactor;
        slippageFactor = _slippageFactor;
        uniRouterAddress = _uniRouterAddress;

        emit SetSettings(
            _controllerFee,
            _withdrawFeeFactor,
            _slippageFactor,
            _uniRouterAddress
        );
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
        address[] memory _path,
        address _to
    ) internal {
        uint256[] memory amounts = ICamelotRouter(uniRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];

        ICamelotRouter(uniRouterAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn,
            amountOut.mul(slippageFactor).div(1000),
            _path,
            _to,
            0x0000000000000000000000000000000000000000,
            now.add(600)
        );
    }
    
    function _safeSwapToAsset(
        uint256 _amountIn,
        address[] memory _path,
        address _to
    ) internal {
        IWombatRouter(wombatRouterAddress).swapExactTokensForTokens(
            _path,
            poolPath,
            _amountIn,
            0,
            _to,
            now.add(600)
        );
    }
}
