// SPDX-License-Identifier: MIT
//A product of https://keyoflife.fi

pragma solidity ^0.8.13;
import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";

import "./ISolidlyRouter.sol";
import "./ISolidlyGauge.sol";
import "./IGasPrice.sol";
import "./FeeManager.sol";
import "./IKeySolidly.sol";

contract KolStrategySolidlyV3 is Initializable, UUPSUpgradeable, FeeManager {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Tokens used
    IERC20Upgradeable public want;
    address public  native;
    address public  output;
    address public  lpToken0;
    address public  lpToken1;

    // Third party contracts
    ISolidlyGauge public  gauge;
    IGasPrice public  gasprice;
    bool public stable;
    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    address[] public rewards;
    ISolidlyRouter.route[] public outputToNativeRoute;
    ISolidlyRouter.route[] public outputToLp0Route;
    ISolidlyRouter.route[] public outputToLp1Route;

    uint256  lp0Decimals;
    uint256  lp1Decimals;

    event StratHarvest(
        address indexed harvester,
        uint256 wantHarvested,
        uint256 tvl
    );

    /* New code */
    bool public feeInDexNative;
    uint256 public totalDexFee;
    uint256 public totalNativeFee;

    uint256 public startingDate;

    uint256 public totalProtocolFee;
    uint256 public protocolFee;
    address public protocolReceiver;

    uint256 public totalHarvested;
    uint256 public withdrawalFee;
    uint256 public depositFee;

    IKeySolidly public keyToken;
    bool public boosted;

    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __AuthUpgradeable_init();

        totalPerformanceFee = 1000;          //  5.00%
        callFee=0;                      //  1% of MAX_FEE
        strategistFee=0;                //  0% of MAX_FEE
        coFee = MAX_FEE - (strategistFee + callFee);

        keeper = 0xbB8707d7365DD9fA686a7EE8C178d69768c4C4C5; //LIBERA LAM
        strategist = 0x5A4A661594f978db52cD1BBEB36df05E6dd4E143;
        coFeeRecipient = 0x4Dfa03c64ABd96359B77E7cCa8219B451C19f27E;
        protocolReceiver = 0x4Dfa03c64ABd96359B77E7cCa8219B451C19f27E;

        harvestOnDeposit = true;
        feeInDexNative = false;

    }

    function updateRoutes(ISolidlyRouter.route[] memory _outputToLp0Route, ISolidlyRouter.route[] memory _outputToLp1Route) external onlyOwner {
        if (outputToLp0Route.length>0) {
            require(_outputToLp0Route[0].from == output
                && _outputToLp0Route[_outputToLp0Route.length-1].to == lpToken0,"path0");
        }
        delete outputToLp0Route;
        for (uint i; i < _outputToLp0Route.length; ++i) {
            outputToLp0Route.push(_outputToLp0Route[i]);
        }
        if (outputToLp1Route.length>0) {
            require(_outputToLp1Route[0].from == output
                && _outputToLp1Route[_outputToLp1Route.length-1].to == lpToken1,"path1");
        }

        delete outputToLp1Route;
        for (uint i; i < _outputToLp1Route.length; ++i) {
            outputToLp1Route.push(_outputToLp1Route[i]);
        }
    }

    function initParams(address _dexRouter, address _dexNative, address _chainNative, address _lpToken0,
        address _lpToken1, bool _stable, address _gauge,
        ISolidlyRouter.route[] memory _outputToLp0Route, ISolidlyRouter.route[] memory _outputToLp1Route,
        address _vault, address _gasprice) external onlyOwner {

        require(address(want) == address(0),"params initialized");

        uniRouter = _dexRouter;
        output = _dexNative;
        native = _chainNative;
        outputToNativeRoute.push(ISolidlyRouter.route(output,native,false));
        gasprice = IGasPrice(_gasprice);
        address _want = ISolidlyRouter(uniRouter).pairFor(_lpToken0, _lpToken1, _stable);
        want = IERC20Upgradeable(_want);
        gauge = ISolidlyGauge(_gauge);
        stable = _stable;
        lpToken0 = _lpToken0;
        lpToken1 = _lpToken1;

        if (_outputToLp0Route.length>0) require(_outputToLp0Route[0].from == output && _outputToLp0Route[_outputToLp0Route.length-1].to == lpToken0,"path0");
        for (uint i; i < _outputToLp0Route.length; ++i) {
            outputToLp0Route.push(_outputToLp0Route[i]);
        }

        if (_outputToLp1Route.length>0) require(_outputToLp1Route[0].from == output && _outputToLp1Route[_outputToLp1Route.length-1].to == lpToken1,"path1");
        for (uint i; i < _outputToLp1Route.length; ++i) {
            outputToLp1Route.push(_outputToLp1Route[i]);
        }


        bytes memory data;
        uint decimals;
        (, data) = lpToken0.call(abi.encodeWithSignature("decimals()"));
        assembly {
            decimals := mload(add(data, add(0x20, 0)))
        }
        lp0Decimals = 10 ** decimals;

        (, data) = lpToken1.call(abi.encodeWithSignature("decimals()"));
        assembly {
            decimals := mload(add(data, add(0x20, 0)))
        }
        lp1Decimals = 10 ** decimals;

        rewards.push(output);

        _giveAllowances();

        startingDate = block.timestamp;
        setVault(_vault);
        emit ParamsInitialized(address(want));
    }

    modifier gasThrottle() {
        require(
            !gasprice.enabled() || tx.gasprice <= gasprice.maxGasPrice(),
            "Strategy: GAS_TOO_HIGH"
        );
        _;
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = want.balanceOf(address(this));
        if (depositFee>0) {
            uint256 _fee = wantBal * depositFee / 10000;
            want.safeTransfer(coFeeRecipient,_fee);
            wantBal -= _fee;
        }

        if (wantBal > 0) {
            if (boosted) {
                keyToken.depositForStrategy(address(gauge), wantBal);
            } else {
                gauge.deposit(wantBal, 0);
            }
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        address _vault = vault;
        require(msg.sender == _vault, "Strategy: VAULT_ONLY");

        uint256 wantBal = want.balanceOf(address(this));
        if (wantBal < _amount) {
            if (boosted) {
                keyToken.withdrawForStrategy(address(gauge), _amount - wantBal);
            } else {
                gauge.withdraw(_amount - wantBal);
            }
            wantBal = want.balanceOf(address(this));
        }
        if (wantBal > _amount) {
            wantBal = _amount;
        }
        if (withdrawalFee>0) {
            uint256 _fee = wantBal * withdrawalFee / 10000;
            want.safeTransfer(coFeeRecipient,_fee);
            wantBal -= _fee;
        }
        want.safeTransfer(_vault, wantBal);
        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external virtual override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "Strategy: VAULT_ONLY");
            _harvest(tx.origin);
        }
    }

    function harvest() external virtual gasThrottle onlyEOA {
        _harvest(tx.origin);
    }

    function harvest(
        address callFeeRecipient
    ) external virtual gasThrottle onlyEOA {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        address[] memory tokens = new address[](1);
        tokens[0] = output;
        if (boosted) {
            keyToken.getRewardsForStrategySimple();
            //keyToken.getRewardsForStrategy(address(gauge), tokens);
        } else {
            gauge.getReward(address(this), tokens);
        }

        uint256 outputBal = IERC20Upgradeable(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            uint256 wantHarvested;
            if (IERC20Upgradeable(output).balanceOf(address(this))>0) {
                addLiquidity();
                wantHarvested = balanceOfWant();
                uint256 _toProtocol;
                if (protocolFee>0) {
                    _toProtocol = wantHarvested * protocolFee / PERCENTAGE ;
                    totalProtocolFee += _toProtocol;
                    want.transfer(protocolReceiver, _toProtocol);
                }
                totalHarvested += wantHarvested - _toProtocol;
                deposit();
            }

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        uint256 outputBal = IERC20Upgradeable(output).balanceOf(address(this));
        uint256 toNative = (outputBal * totalPerformanceFee) / PERCENTAGE;
        totalDexFee += toNative;

        if (feeInDexNative) {
            IERC20Upgradeable(output).safeTransfer(coFeeRecipient, toNative);
            emit ChargedFees(0, toNative, 0);
            return;
        }

        ISolidlyRouter(uniRouter).swapExactTokensForTokens(
            toNative,
            0,
            outputToNativeRoute,
            address(this),
            block.timestamp
        );

        uint256 nativeBal = IERC20Upgradeable(native).balanceOf(address(this));
        totalNativeFee += nativeBal;

        uint256 callFeeAmount = (nativeBal * callFee) / MAX_FEE;
        IERC20Upgradeable(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 coFeeAmount = (nativeBal * coFee) / MAX_FEE;
        IERC20Upgradeable(native).safeTransfer(coFeeRecipient, coFeeAmount);

        uint256 strategistFeeAmount = (nativeBal * strategistFee) / MAX_FEE;
        IERC20Upgradeable(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, coFeeAmount, strategistFeeAmount);
    }

    function calcLiquidity(uint256 outputBal) public view returns (uint256 lp0Amt, uint256 lp1Amt) {
        lp0Amt = outputBal / 2;
        lp1Amt = outputBal - lp0Amt;

        if (stable) {
            ISolidlyRouter router = ISolidlyRouter(uniRouter);
            uint256 out0 = lp0Amt;
            if (lpToken0 != output) {
                out0 = router.getAmountsOut(lp0Amt, outputToLp0Route)[outputToLp0Route.length];
            }
            out0 = out0 * 1e18 / lp0Decimals;

            uint256 out1 = lp1Amt;
            if (lpToken1 != output) {
                out1 = router.getAmountsOut(lp1Amt, outputToLp1Route)[outputToLp1Route.length];
            }
            out1 = out1 * 1e18 / lp1Decimals;

            (uint256 amountA, uint256 amountB, ) = router.quoteAddLiquidity(
                lpToken0,
                lpToken1,
                stable,
                out0,
                out1
            );

            amountA = (amountA * 1e18) / lp0Decimals;
            amountB = (amountB * 1e18) / lp1Decimals;
            uint256 ratio = (((out0 * 1e18) / out1) * amountB) / amountA;
            lp0Amt = (outputBal * 1e18) / (ratio + 1e18);
            lp1Amt = outputBal - lp0Amt;
        }
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        (uint256 lp0Amt, uint256 lp1Amt) = calcLiquidity(IERC20Upgradeable(output).balanceOf(address(this)));

        ISolidlyRouter router = ISolidlyRouter(uniRouter);

        if (lpToken0 != output) {
            router.swapExactTokensForTokens(
                lp0Amt,
                0,
                outputToLp0Route,
                address(this),
                block.timestamp
            );
        }

        if (lpToken1 != output) {
            router.swapExactTokensForTokens(
                lp1Amt,
                0,
                outputToLp1Route,
                address(this),
                block.timestamp
            );
        }

        uint256 lp0Bal = IERC20Upgradeable(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20Upgradeable(lpToken1).balanceOf(address(this));
        router.addLiquidity(
            lpToken0,
            lpToken1,
            stable,
            lp0Bal,
            lp1Bal,
            1,
            1,
            address(this),
            block.timestamp
        );
    }

    // calculate the total 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        if (boosted)
            return keyToken.balanceOfStrategy(address(gauge));
        else
            return gauge.balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        if (boosted){
            return keyToken.earnedOfStrategy(address(gauge), output);
        }
        else
            return gauge.earned(output, address(this));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        if (feeInDexNative) return 0;
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            uint256[] memory amountsOut = ISolidlyRouter(uniRouter)
            .getAmountsOut(outputBal, outputToNativeRoute);
            nativeOut = amountsOut[amountsOut.length - 1];
        }
        return
        (((nativeOut * totalPerformanceFee) / PERCENTAGE) * callFee) /
        MAX_FEE;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        emit SetHarvestOnDeposit(_harvestOnDeposit);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        if (boosted) {
            keyToken.withdrawAllForStrategy(address(gauge));
        } else {
            gauge.withdrawAll();
        }

        uint256 wantBal = want.balanceOf(address(this));
        emit Panic(wantBal);
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
        address _uniRouter = uniRouter;
        /*
        want.safeApprove(address(gauge), 0);
        IERC20Upgradeable(output).safeApprove(_uniRouter, 0);
        IERC20Upgradeable(lpToken0).safeApprove(_uniRouter, 0);
        IERC20Upgradeable(lpToken1).safeApprove(_uniRouter, 0);

        want.safeApprove(address(gauge), type(uint).max);
        IERC20Upgradeable(output).safeApprove(_uniRouter, type(uint).max);
        IERC20Upgradeable(lpToken0).safeApprove(_uniRouter, type(uint).max);
        IERC20Upgradeable(lpToken1).safeApprove(_uniRouter, type(uint).max);
        */
        want.approve(address(gauge), type(uint).max);
        IERC20Upgradeable(output).approve(_uniRouter, type(uint).max);
        IERC20Upgradeable(lpToken0).approve(_uniRouter, type(uint).max);
        IERC20Upgradeable(lpToken1).approve(_uniRouter, type(uint).max);

        emit GiveAllowances();
    }

    function _removeAllowances() internal {
        address _uniRouter = uniRouter;
        want.safeApprove(address(gauge), 0);
        IERC20Upgradeable(output).safeApprove(_uniRouter, 0);
        IERC20Upgradeable(lpToken0).safeApprove(_uniRouter, 0);
        IERC20Upgradeable(lpToken1).safeApprove(_uniRouter, 0);
        emit RemoveAllowances();
    }

    function _solidlyToRoute(
        ISolidlyRouter.route[] memory _route
    ) internal pure returns (address[] memory) {
        address[] memory route = new address[](_route.length + 1);
        route[0] = _route[0].from;
        for (uint i; i < _route.length; ++i) {
            route[i + 1] = _route[i].to;
        }
        return route;
    }

    function outputToNative() external view returns (address[] memory) {
        ISolidlyRouter.route[] memory _route = outputToNativeRoute;
        return _solidlyToRoute(_route);
    }

    function outputToLp0() external view returns (address[] memory) {
        ISolidlyRouter.route[] memory _route = outputToLp0Route;
        return _solidlyToRoute(_route);
    }

    function outputToLp1() external view returns (address[] memory) {
        ISolidlyRouter.route[] memory _route = outputToLp1Route;
        return _solidlyToRoute(_route);
    }

    function set_ProtocolFee(uint256 _protocolFee, address _protocolReceiver) external  onlyManager {
        require(_protocolFee <= 2000, "FeeManager: protocolFee > 20%");
        require(_protocolReceiver != address(0), "FeeManager: protocolReceiver = address(0)");
        protocolFee = _protocolFee;
        protocolReceiver = _protocolReceiver;
        emit SetProtocolFee(_protocolFee,_protocolReceiver);
    }

    function set_feeInDexNative(bool _feeInDexNative) external  onlyManager {
        feeInDexNative = _feeInDexNative;
        emit SetFeeInDexNative(_feeInDexNative);
    }

    function set_DepositWithdrawalFees(uint256 _withdrawalFee, uint256 _depositFee) external onlyManager {
        require(_withdrawalFee <= 1000, "Withdrawal fee is too high");
        require(_depositFee <= 1000, "Deposit fee is too high");
        withdrawalFee = _withdrawalFee;
        depositFee = _depositFee;
        emit SetDepositWithdrawalFees(_withdrawalFee, _depositFee);
    }

    function updateGauge(address _gauge) external onlyOwner {
        want.approve(_gauge, type(uint).max);
        gauge = ISolidlyGauge(_gauge);
    }
    /*
        function set_Boosted(bool _value, address _keyToken) public onlyOwner {
            require(_value!=boosted,"nothing change");
            if (_value==false) {//change to gauge
                _harvest(msg.sender);
                keyToken.withdrawAllForStrategy(address(gauge));
                boosted = false;
                deposit();
            } else {
                _harvest(msg.sender);
                gauge.withdrawAll();
                boosted = true;
                keyToken = IKeySolidly(_keyToken);
                want.approve(address(keyToken), type(uint).max);
                deposit();
            }
        }

        function updateNativeRoute() external onlyOwner {
            delete outputToNativeRoute;
            outputToNativeRoute.push(ISolidlyRouter.route(output,0x80487b4f8f70e793A81a42367c225ee0B94315DF,false));
            outputToNativeRoute.push(ISolidlyRouter.route(0x80487b4f8f70e793A81a42367c225ee0B94315DF,native,false));
        }
    */

    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 coFees, uint256 strategistFees);
    event GiveAllowances();
    event RemoveAllowances();
    event SetHarvestOnDeposit(bool isEnabled);
    event SetFeeInDexNative(bool isEnabled);
    event RetireStrategy(address vault, uint256 amount);
    event SetProtocolFee(uint256 _protocolFee, address _protocolReceiver);
    event SetDepositWithdrawalFees(uint256 _withdrawalFee,  uint256 _depositFee);
    event ParamsInitialized(address _want);
    event Panic(uint256 balance);

    function updateV2() external onlyOwner {
    }

}


