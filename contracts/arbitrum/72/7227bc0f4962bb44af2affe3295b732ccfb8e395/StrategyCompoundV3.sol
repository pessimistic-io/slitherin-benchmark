// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20.sol";

import "./IERC20Extended.sol";
import "./StratFeeManagerInitializable.sol";
import "./UniV3Actions.sol";
import "./UniswapV3Utils.sol";

interface IComet {
    function supply(address asset, uint amount) external;
    function withdraw(address asset, uint amount) external;
    function balanceOf(address user) external view returns (uint256);
    function baseToken() external view returns (address);
}

interface ICometRewards {
    function claim(address comet, address source, bool shouldAccrue) external;
}

contract StrategyCompoundV3 is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public constant native = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant output = 0x354A6dA3fcde098F8389cad84b0182725c6C91dE;
    address public want;
    address public cToken;

    // Third party contracts
    ICometRewards public constant rewards = ICometRewards(0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae);
    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    
    bytes public outputToNativePath;
    bytes public nativeToWantPath;
    

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _cToken,
        bytes calldata _outputToNativePath,
        bytes calldata _nativeToWantPath,
        CommonAddresses calldata _commonAddresses
     ) public initializer  {
        __StratFeeManager_init(_commonAddresses);
        cToken = _cToken;
        want = IComet(cToken).baseToken();

        setOutputToNative(_outputToNativePath);
        setNativeToWant(_nativeToWantPath);

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 bal = balanceOfWant();

        if (bal > 0) {
            IComet(cToken).supply(want, bal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            uint256 toWithdraw = _amount - wantBal;
            uint256 cTokenBal = IERC20(want).balanceOf(cToken);
            require(cTokenBal > toWithdraw, "Not Enough Underlying");

            IComet(cToken).withdraw(want, toWithdraw);
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = _amount * withdrawalFee / WITHDRAWAL_MAX;
            _amount = _amount - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, _amount);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external virtual override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        uint256 bal = IERC20(output).balanceOf(address(this));
        rewards.claim(cToken, address(this), true);
        if (bal > 0) {
            swapRewardsToNative();
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function swapRewardsToNative() internal {
        uint bal = IERC20(output).balanceOf(address(this));
        if (bal > 0) {
            UniV3Actions.swapV3WithDeadline(unirouter, outputToNativePath, bal);
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
        uint256 bal = IERC20(native).balanceOf(address(this));
        if (nativeToWantPath.length > 0) {
            UniV3Actions.swapV3WithDeadline(unirouter, nativeToWantPath, bal);
        }

        deposit();
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return IComet(cToken).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public pure returns (uint256) {
        return 0;
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

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IComet(cToken).withdraw(want, balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {

        IComet(cToken).withdraw(want, balanceOfPool());
        pause();
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
        IERC20(output).approve(unirouter, type(uint).max);
        IERC20(native).approve(unirouter, type(uint).max);
        IERC20(want).approve(cToken, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(output).approve(unirouter, 0);
        IERC20(native).approve(unirouter, 0);
        IERC20(want).approve(cToken, 0);
    }

    function setOutputToNative(bytes calldata _outputToNativePath) public onlyOwner {
        if (_outputToNativePath.length > 0) {
            address[] memory route = UniswapV3Utils.pathToRoute(_outputToNativePath);
            require(route[0] == output, "!output");
        }
        outputToNativePath = _outputToNativePath;
    }

    function setNativeToWant(bytes calldata _nativeToWantPath) public onlyOwner {
        if (_nativeToWantPath.length > 0) {
            address[] memory route = UniswapV3Utils.pathToRoute(_nativeToWantPath);
            require(route[0] == native, "!native");
            require(route[route.length - 1] == want, "!want");
        }
        nativeToWantPath = _nativeToWantPath;
    }

    function outputToNative() external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(outputToNativePath);
    }

    function nativeToWant() external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(nativeToWantPath);
    }
}
