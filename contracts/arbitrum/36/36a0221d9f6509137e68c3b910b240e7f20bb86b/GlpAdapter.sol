//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20, IERC20Metadata} from "./IERC20Metadata.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC4626} from "./IERC4626.sol";
import {IGmxRewardRouter} from "./IGmxRewardRouter.sol";
import {IGlpManager, IGMXVault} from "./IGlpManager.sol";
import {IJonesGlpVaultRouter} from "./IJonesGlpVaultRouter.sol";
import {Operable, Governable} from "./Operable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {MerkleProof} from "./MerkleProof.sol";
import {WhitelistController} from "./WhitelistController.sol";
import {IAggregatorV3} from "./IAggregatorV3.sol";
import {JonesGlpLeverageStrategy} from "./JonesGlpLeverageStrategy.sol";
import {JonesGlpStableVault} from "./JonesGlpStableVault.sol";

contract GlpAdapter is Operable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IJonesGlpVaultRouter public vaultRouter;
    IGmxRewardRouter public gmxRouter = IGmxRewardRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
    IAggregatorV3 public oracle = IAggregatorV3(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3);
    IERC20 public glp = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);
    IERC20 public usdc = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    WhitelistController public controller;
    JonesGlpLeverageStrategy public strategy;
    JonesGlpStableVault public stableVault;
    address public socket;

    uint256 public flexibleTotalCap;
    bool public hatlistStatus;
    bool public useFlexibleCap;

    mapping(address => bool) public isValid;

    uint256 public constant BASIS_POINTS = 1e12;

    constructor(address[] memory _tokens, address _controller, address _strategy, address _stableVault, address _socket)
        Governable(msg.sender)
    {
        uint8 i = 0;
        for (; i < _tokens.length;) {
            _editToken(_tokens[i], true);
            unchecked {
                i++;
            }
        }

        controller = WhitelistController(_controller);
        strategy = JonesGlpLeverageStrategy(_strategy);
        stableVault = JonesGlpStableVault(_stableVault);
        socket = _socket;
    }

    function zapToGlp(address _token, uint256 _amount, bool _compound)
        external
        nonReentrant
        validToken(_token)
        returns (uint256)
    {
        _onlyEOA();

        IERC20(_token).transferFrom(msg.sender, address(this), _amount);

        IERC20(_token).approve(gmxRouter.glpManager(), _amount);
        uint256 mintedGlp = gmxRouter.mintAndStakeGlp(_token, _amount, 0, 0);

        glp.approve(address(vaultRouter), mintedGlp);
        uint256 receipts = vaultRouter.depositGlp(mintedGlp, msg.sender, _compound);

        return receipts;
    }

    function zapToGlpEth(bool _compound) external payable nonReentrant returns (uint256) {
        _onlyEOA();

        uint256 mintedGlp = gmxRouter.mintAndStakeGlpETH{value: msg.value}(0, 0);

        glp.approve(address(vaultRouter), mintedGlp);

        uint256 receipts = vaultRouter.depositGlp(mintedGlp, msg.sender, _compound);

        return receipts;
    }

    function redeemGlpBasket(uint256 _shares, bool _compound, address _token, bool _native)
        external
        nonReentrant
        validToken(_token)
        returns (uint256)
    {
        _onlyEOA();

        uint256 assetsReceived = vaultRouter.redeemGlpAdapter(_shares, _compound, _token, msg.sender, _native);

        return assetsReceived;
    }

    function depositGlp(uint256 _assets, bool _compound) external nonReentrant returns (uint256) {
        _onlyEOA();

        glp.transferFrom(msg.sender, address(this), _assets);

        glp.approve(address(vaultRouter), _assets);

        uint256 receipts = vaultRouter.depositGlp(_assets, msg.sender, _compound);

        return receipts;
    }

    function depositStable(uint256 _assets, bool _compound) external nonReentrant returns (uint256) {
        _onlyEOA();

        if (useFlexibleCap) {
            _checkUsdcCap(_assets);
        }

        usdc.transferFrom(msg.sender, address(this), _assets);

        usdc.approve(address(vaultRouter), _assets);

        uint256 receipts = vaultRouter.depositStable(_assets, _compound, msg.sender);

        return receipts;
    }

    // MultiChain Deposits

    function multichainZapToGlp(address _receiver, address _token, bool _compound)
        external
        nonReentrant
        returns (uint256)
    {
        IERC20 token = IERC20(_token);

        uint256 amount = token.allowance(msg.sender, address(this));

        if (amount == 0 || !isValid[_token]) {
            return 0;
        }

        token.transferFrom(msg.sender, address(this), amount);

        if (!_onlySocket()) {
            token.transfer(_receiver, amount);
            return 0;
        }

        if (!_onlyAllowed(_receiver)) {
            return 0;
        }

        address glpManager = gmxRouter.glpManager();
        token.approve(glpManager, amount);

        uint256 mintedGlp;

        try gmxRouter.mintAndStakeGlp(_token, amount, 0, 0) returns (uint256 glpAmount) {
            mintedGlp = glpAmount;
        } catch {
            token.transfer(_receiver, amount);
            token.safeDecreaseAllowance(glpManager, amount);
            return 0;
        }

        address routerAddress = address(vaultRouter);

        glp.approve(routerAddress, mintedGlp);

        try vaultRouter.depositGlp(mintedGlp, _receiver, _compound) returns (uint256 receipts) {
            return receipts;
        } catch {
            glp.transfer(_receiver, mintedGlp);
            glp.approve(routerAddress, 0);
            return 0;
        }
    }

    function multichainZapToGlpEth(address payable _receiver, bool _compound)
        external
        payable
        nonReentrant
        returns (uint256)
    {
        if (msg.value == 0) {
            return 0;
        }

        if (!_onlySocket()) {
            (bool sent,) = _receiver.call{value: msg.value}("");
            if (!sent) {
                revert SendETHFail();
            }
            return 0;
        }

        if (!_onlyAllowed(_receiver)) {
            return 0;
        }

        uint256 mintedGlp;

        try gmxRouter.mintAndStakeGlpETH{value: msg.value}(0, 0) returns (uint256 glpAmount) {
            mintedGlp = glpAmount;
        } catch {
            (bool sent,) = _receiver.call{value: msg.value}("");
            if (!sent) {
                revert SendETHFail();
            }
            return 0;
        }

        address routerAddress = address(vaultRouter);

        glp.approve(routerAddress, mintedGlp);

        try vaultRouter.depositGlp(mintedGlp, _receiver, _compound) returns (uint256 receipts) {
            return receipts;
        } catch {
            glp.transfer(_receiver, mintedGlp);
            glp.approve(routerAddress, 0);
            return 0;
        }
    }

    function multichainDepositStable(address _receiver, bool _compound) external nonReentrant returns (uint256) {
        uint256 amount = usdc.allowance(msg.sender, address(this));

        if (amount == 0) {
            return 0;
        }

        usdc.transferFrom(msg.sender, address(this), amount);

        if (!_onlySocket()) {
            usdc.transfer(_receiver, amount);
            return 0;
        }

        if (!_onlyAllowed(_receiver)) {
            return 0;
        }

        address routerAddress = address(vaultRouter);

        usdc.approve(routerAddress, amount);

        try vaultRouter.depositStable(amount, _compound, _receiver) returns (uint256 receipts) {
            return receipts;
        } catch {
            usdc.transfer(_receiver, amount);
            usdc.safeDecreaseAllowance(routerAddress, amount);
            return 0;
        }
    }

    function rescueFunds(address _token, address _userAddress, uint256 _amount) external onlyGovernor {
        IERC20(_token).safeTransfer(_userAddress, _amount);
    }

    function updateGmxRouter(address _gmxRouter) external onlyGovernor {
        gmxRouter = IGmxRewardRouter(_gmxRouter);
    }

    function updateVaultRouter(address _vaultRouter) external onlyGovernor {
        vaultRouter = IJonesGlpVaultRouter(_vaultRouter);
    }

    function updateStrategy(address _strategy) external onlyGovernor {
        strategy = JonesGlpLeverageStrategy(_strategy);
    }

    function updateSocket(address _socket) external onlyGovernor {
        socket = _socket;
    }

    function _editToken(address _token, bool _valid) internal {
        isValid[_token] = _valid;
    }

    function toggleHatlist(bool _status) external onlyGovernor {
        hatlistStatus = _status;
    }

    function toggleFlexibleCap(bool _status) external onlyGovernor {
        useFlexibleCap = _status;
    }

    function updateFlexibleCap(uint256 _newAmount) public onlyGovernor {
        //18 decimals -> $1mi = 1_000_000e18
        flexibleTotalCap = _newAmount;
    }

    function getFlexibleCap() public view returns (uint256) {
        return flexibleTotalCap; //18 decimals
    }

    function usingFlexibleCap() public view returns (bool) {
        return useFlexibleCap;
    }

    function usingHatlist() public view returns (bool) {
        return hatlistStatus;
    }

    function getUsdcCap() public view returns (uint256 usdcCap) {
        usdcCap = (flexibleTotalCap * (strategy.getTargetLeverage() - BASIS_POINTS)) / strategy.getTargetLeverage();
    }

    function belowCap(uint256 _amount) public view returns (bool) {
        uint256 increaseDecimals = 10;
        (, int256 lastPrice,,,) = oracle.latestRoundData(); //8 decimals
        uint256 price = uint256(lastPrice) * (10 ** increaseDecimals); //18 DECIMALS
        uint256 usdcCap = getUsdcCap(); //18 decimals
        uint256 stableTvl = stableVault.tvl(); //18 decimals
        uint256 denominator = 1e6;

        uint256 notional = (price * _amount) / denominator;

        if (stableTvl + notional > usdcCap) {
            return false;
        }

        return true;
    }

    function _onlyEOA() private view {
        if (msg.sender != tx.origin && !controller.isWhitelistedContract(msg.sender)) {
            revert NotWhitelisted();
        }
    }

    function _onlySocket() private view returns (bool) {
        if (msg.sender == socket) {
            return true;
        }
        return false;
    }

    function _onlyAllowed(address _receiver) private view returns (bool) {
        if (isContract(_receiver) && !controller.isWhitelistedContract(_receiver)) {
            return false;
        }
        return true;
    }

    function isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function _checkUsdcCap(uint256 _amount) private view {
        if (!belowCap(_amount)) {
            revert OverUsdcCap();
        }
    }

    function editToken(address _token, bool _valid) external onlyGovernor {
        _editToken(_token, _valid);
    }

    modifier validToken(address _token) {
        require(isValid[_token], "Invalid token.");
        _;
    }

    error NotHatlisted();
    error OverUsdcCap();
    error NotWhitelisted();
    error SendETHFail();
}

