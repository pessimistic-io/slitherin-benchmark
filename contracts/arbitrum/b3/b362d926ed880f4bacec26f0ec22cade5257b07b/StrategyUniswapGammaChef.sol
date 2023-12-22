// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20.sol";

import "./ISolidlyPair.sol";
import "./IMiniChefV2.sol";
import "./IRewarder.sol";
import "./IERC20Extended.sol";
import "./StratFeeManagerInitializable.sol";
import "./GasFeeThrottler.sol";
import "./UniswapV3Utils.sol";

interface IGammaUniProxy {
    function getDepositAmount(address pos, address token, uint _deposit) external view returns (uint amountStart, uint amountEnd);
    function deposit(uint deposit0, uint deposit1, address to, address pos, uint[4] memory minIn) external returns (uint shares);
}

interface IGammaPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function pool() external view returns (address);
}

interface IUniswapV3Pool {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
}

interface IUniswapQuoter {
    function quoteExactInput(bytes memory path, uint amountIn) external returns (uint amountOut);
}

interface IHypervisor {
    function whitelistedAddress() external view returns (address uniProxy);
}

contract StrategyUniswapGammaChef is StratFeeManagerInitializable, GasFeeThrottler {
    using SafeERC20 for IERC20;

    uint256 private constant DURATION = 1 days;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public chef;
    IUniswapQuoter public quoter;

    bool public isFastQuote;
    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    uint256 public pid;
    
    bytes public outputToNativePath;
    bytes public nativeToLp0Path;
    bytes public nativeToLp1Path;

    mapping (address => bytes) public rewardsPath; 
    address[] public rewards;
    uint256 public totalLocked;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        address _chef,
        uint256 _pid, 
        bytes calldata _outputToNativePath,
        bytes calldata _nativeToLp0Path,
        bytes calldata _nativeToLp1Path,
        CommonAddresses calldata _commonAddresses
     ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        chef = _chef;
        pid = _pid;

        lpToken0 = IGammaPool(want).token0();
        lpToken1 = IGammaPool(want).token1();

        address[] memory route = UniswapV3Utils.pathToRoute(_outputToNativePath);
        output = route[0];
        native = route[route.length - 1];

        setOutputToNative(_outputToNativePath);
        setNativeToLp0(_nativeToLp0Path);
        setNativeToLp1(_nativeToLp1Path);

        quoter = IUniswapQuoter(0xB048Bbc1Ee6b733FFfCFb9e9CeF7375518e25997);
        harvestOnDeposit = true;
        withdrawalFee = 0;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMiniChefV2(chef).deposit(pid, wantBal, address(this));
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMiniChefV2(chef).withdraw(pid, _amount - wantBal, address(this));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal * withdrawalFee / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external virtual override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external gasThrottle virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external gasThrottle virtual {
        _harvest(callFeeRecipient);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IMiniChefV2(chef).harvest(pid, address(this));
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        uint256 before = balanceOfWant();
        if (outputBal > 0) {
            swapRewardsToNative();
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant() - before;
            totalLocked = wantHarvested + lockedProfit();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function swapRewardsToNative() internal {
        uint bal = IERC20(output).balanceOf(address(this));
        if (bal > 0) UniswapV3Utils.swap(unirouter, outputToNativePath, bal);

        for (uint i; i < rewards.length; ++i) {
            uint rewardBal = IERC20(rewards[i]).balanceOf(address(this));
            if (rewardBal > 0) UniswapV3Utils.swap(unirouter, rewardsPath[rewards[i]], rewardBal);
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        (uint toLp0, uint toLp1) = quoteAddLiquidity();

        if (nativeToLp0Path.length > 0) {
            UniswapV3Utils.swap(unirouter, nativeToLp0Path, toLp0);
        }
        if (nativeToLp1Path.length > 0) {
            UniswapV3Utils.swap(unirouter, nativeToLp1Path, toLp1);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));

        (uint amount1Start, uint amount1End) = gammaProxy().getDepositAmount(want, lpToken0, lp0Bal);
        (, uint amount0End) = gammaProxy().getDepositAmount(want, lpToken1, lp1Bal);
        if (lp1Bal > amount1End) {
            lp1Bal = amount1End;
        } else if (lp1Bal < amount1Start) {
            (, lp0Bal) = gammaProxy().getDepositAmount(want, lpToken1, lp1Bal);
        }
        
        if (lp0Bal > amount0End) {
            lp0Bal = amount0End;
        }

        uint[4] memory minIn;
        gammaProxy().deposit(lp0Bal, lp1Bal, address(this), want, minIn);

    }

    function quoteAddLiquidity() internal returns (uint toLp0, uint toLp1) {
        uint nativeBal = IERC20(native).balanceOf(address(this));
        uint ratio;

        if (isFastQuote) {
            uint lp0Decimals = 10**IERC20Extended(lpToken0).decimals();
            uint lp1Decimals = 10**IERC20Extended(lpToken1).decimals();
            uint decimalsDiff = 1e18 * lp0Decimals / lp1Decimals;
            uint decimalsDenominator = decimalsDiff > 1e12 ? 1e6 : 1;
            (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(IGammaPool(want).pool()).slot0();
            uint price = uint256(sqrtPriceX96) ** 2 * (decimalsDiff / decimalsDenominator) / (2 ** 192) * decimalsDenominator;
            (uint amountStart, uint amountEnd) = gammaProxy().getDepositAmount(want, lpToken0, lp0Decimals);
            uint amountB = (amountStart + amountEnd) / 2 * 1e18 / lp1Decimals;
            ratio = amountB * 1e18 / price;
        } else {
            uint lp0Amt = nativeBal / 2;
            uint lp1Amt = nativeBal - lp0Amt;
            uint out0 = lp0Amt;
            uint out1 = lp1Amt;
            if (nativeToLp0Path.length > 0) {
                out0 = quoter.quoteExactInput(nativeToLp0Path, lp0Amt);
            }
            if (nativeToLp1Path.length > 0) {
                out1 = quoter.quoteExactInput(nativeToLp1Path, lp1Amt);
            }
            (uint amountStart, uint amountEnd) = gammaProxy().getDepositAmount(want, lpToken0, out0);
            uint amountB = (amountStart + amountEnd) / 2;
            ratio = amountB * 1e18 / out1;
        }

        toLp0 = nativeBal * 1e18 / (ratio + 1e18);
        toLp1 = nativeBal - toLp0;
    }

    function setFastQuote(bool _isFastQuote) external onlyManager {
        isFastQuote = _isFastQuote;
    }

    function addReward(address _token, bytes calldata _path) external onlyOwner {
        address[] memory route = UniswapV3Utils.pathToRoute(_path);
        require(route[0] == _token, "!output");
        require(route[route.length -1] == native, "!native");

        IERC20(_token).safeApprove(unirouter, 0);
        IERC20(_token).safeApprove(unirouter, type(uint).max);

        rewards.push(_token);
        rewardsPath[_token] = _path;
    }

    function deleteRewards() external onlyManager {
        for (uint256 i; i < rewards.length; ++i) {
            delete rewardsPath[rewards[i]];
        }

        delete rewards;
    }

    function lockedProfit() public view returns (uint256) {
        uint256 elapsed = block.timestamp - lastHarvest;
        uint256 remaining = elapsed < DURATION ? DURATION - elapsed : 0;
        return totalLocked * remaining / DURATION;
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool() - lockedProfit();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256 amount) {
        (amount,) = IMiniChefV2(chef).userInfo(pid, address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IMiniChefV2(chef).pendingSushi(pid, address(this));
    }

    // native reward amount for calling harvest
    function callReward() public pure returns (uint256) {
        return 0;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        if (balanceOfPool() > 0) {
            IMiniChefV2(chef).emergencyWithdraw(pid, address(this));
        }

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IMiniChefV2(chef).emergencyWithdraw(pid, address(this));
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).approve(chef, type(uint).max);
        IERC20(output).approve(unirouter, type(uint).max);
        IERC20(native).approve(unirouter, type(uint).max);

        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
            IERC20(rewards[i]).safeApprove(unirouter, type(uint).max);
        }

        IERC20(lpToken0).approve(want, 0);
        IERC20(lpToken0).approve(want, type(uint).max);
        IERC20(lpToken1).approve(want, 0);
        IERC20(lpToken1).approve(want, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).approve(chef, 0);
        IERC20(output).approve(unirouter, 0);
        IERC20(native).approve(unirouter, 0);

        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
        }

        IERC20(lpToken0).approve(want, 0);
        IERC20(lpToken1).approve(want, 0);
    }

    function setOutputToNative(bytes calldata _outputToNativePath) public onlyOwner {
        if (_outputToNativePath.length > 0) {
            address[] memory route = UniswapV3Utils.pathToRoute(_outputToNativePath);
            require(route[0] == output, "!output");
        }
        outputToNativePath = _outputToNativePath;
    }

    function setNativeToLp0(bytes calldata _nativeToLp0Path) public onlyOwner {
        if (_nativeToLp0Path.length > 0) {
            address[] memory route = UniswapV3Utils.pathToRoute(_nativeToLp0Path);
            require(route[0] == native, "!native");
            require(route[route.length - 1] == lpToken0, "!lp0");
        }
        nativeToLp0Path = _nativeToLp0Path;
    }

    function setNativeToLp1(bytes calldata _nativeToLp1Path) public onlyOwner {
        if (_nativeToLp1Path.length > 0) {
            address[] memory route = UniswapV3Utils.pathToRoute(_nativeToLp1Path);
            require(route[0] == native, "!native");
            require(route[route.length - 1] == lpToken1, "!lp1");
        }
        nativeToLp1Path = _nativeToLp1Path;
    }

    function gammaProxy() public view returns (IGammaUniProxy uniProxy) {
        uniProxy = IGammaUniProxy(IHypervisor(want).whitelistedAddress());
    }

    function outputToNative() external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(outputToNativePath);
    }

    function nativeToLp0() external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(nativeToLp0Path);
    }

    function nativeToLp1() external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(nativeToLp1Path);
    }

    function rewardsRoute(uint index) external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(rewardsPath[rewards[index]]);
    }
}
