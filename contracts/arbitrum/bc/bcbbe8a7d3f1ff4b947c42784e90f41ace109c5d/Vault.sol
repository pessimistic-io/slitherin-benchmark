// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

import "./ILPToken.sol";
import "./IFeeLP.sol";
import "./IVault.sol";
import "./IRouter.sol";
import "./IVaultPriceFeed.sol";
import "./IVaultUtil.sol";
import "./IReferral.sol";


interface GLPmanager {
    function getAumInUsdg(bool maximise) external view returns (uint256);

    function getPrice(bool _maximise) external view returns (uint256);
}

contract Vault is ReentrancyGuard, IVault {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct ReduceCollateralResult {
        bool hasProfit;
        uint256 LPOut;
        uint256 LPOutAfterFee;
        uint256 profit;
        uint256 feeLPAmount;
    }

    struct FinalDecreasePositionParams {
        address account;
        address receiver;
        bool hasProfit;
        uint256 orignLevel;
        uint256 LPOut;
        uint256 LPOutAfterFee;
        uint256 collateral;
        uint256 insurance;
        uint256 profit;
        uint256 insuranceProportion;
    }

    struct EmitPositionParams {
        uint256 LPOut;
        uint256 LPOutAfterFee;
        uint256 feeLPAmount;
        address account;
        address indexToken;
        uint256 orignLevel;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        uint256 price;
        uint256 insurance;
        uint256 insuranceLevel;
        uint256 payInsurance;
    }

    struct DecreasePositionParams {
        address account;
        address indexToken;
        uint256 sizeDelta;
        uint256 collateralDelta;
        bool isLong;
        address receiver;
        uint256 insuranceLevel; //0-5
        uint256 feeLP;
    }

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    uint256 public constant MIN_LEVERAGE = 10000; // 1x
    uint256 public maxLeverage = 50 * 10000; // 50x
    uint256 public LP_DECIMALS = 18;
    uint256 public USDC_DECIMALS = 6;
    uint256 public PRICE_DECIMALS = 30;
    uint256 public constant MAX_FEE_BASIS_POINTS = 500; // 5%

    bool public isInitialized;
    address public priceFeed;
    address public LPToken;
    address public FeeLP;
    address public usdcToken; //only usdc can buy LP
    address public gov;
    IVaultUtil public vaultUtil; //keep all global data
    address public router;
    address public orderbook;
    uint256 public liquidationFee;
    bool public inPrivateLiquidationMode = true;
    mapping(address => bool) public isLiquidator;

    uint256 public liquidationFeeRate = 100; //1%
    uint256 public taxBasisPoints = 8; // base fee 0.08% for increase decrease
    uint256 public maxGasPrice;
    uint256 public minCollateral = 10e18; //10LP
    //0 no insurance; 1 10%;2 20%;3 30%;4 40%;5 50%
    mapping(uint256 => uint256) public insuranceLevel;
    uint256 public insuranceOdds = 20000; //insurance*2
    uint256 public insuranceFeeRate = 300; //3%
    //index token can open position
    address[] public allWhitelistedTokens;
    mapping(address => bool) public whitelistedTokens;
    //white listed token's decimal
    mapping(address => uint256) public tokenDecimals;

    //if profit have too much change in 2 minutes,profit set 0
    //if profit less than 0,sub from user's size when calculate next price
    uint256 public minProfitTime = 2 minutes; //calculate profit over 2 minutes
    mapping(address => uint256) public minProfitBasisPoints;

    //token=>amount,usdc for buy LP; LP transfer in for open close position
    mapping(address => uint256) public tokenBalances;
    //token=>fee,usdc for buy LP; LP fee for sell LP, open close position
    mapping(address => uint256) public feeReserves;

    //key=>position
    mapping(bytes32 => Position) public positions;

    address public teamAddress;
    address public earnAddress;
    uint256 public toTeamRatio = 2500;
    bool public LPFlag;

    uint256 public maxLiquidateLeverage = 1250 * 10000;

    uint256[50] private _gap;
    event BuyLP(
        address account,
        address receiver,
        address token,
        uint256 tokenAmount,
        uint256 LPAmount
    );

    event SellLP(
        address account,
        address receiver,
        address token,
        uint256 LPAmount,
        uint256 tokenAmount
    );

    event IncreasePosition(
        address account,
        address indexToken,
        uint256 orignLevel,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 price,
        uint256 fee,
        uint256 insurance,
        uint256 insuranceLevel
    );

    event DecreasePosition(
        address account,
        address indexToken,
        uint256 orignLevel,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 price,
        uint256 fee,
        uint256 insurance,
        uint256 insuranceLevel,
        uint256 LPOutAfterFee,
        uint256 payInsurance
    );

    event LiquidatePosition(
        address account,
        address indexToken,
        bool isLong,
        uint256 size,
        uint256 collateral,
        int256 realisedPnl,
        uint256 markPrice,
        uint256 insuranceLevel,
        uint256 marginAdnLiquidateFees,
        uint256 payInsurance
    );

    event UpdatePosition(
        bytes32 key,
        uint256 size,
        uint256 collateral,
        uint256 averagePrice,
        int256 realisedPnl,
        uint256 markPrice,
        uint256 insuranceLevel
    );

    event ClosePosition(
        bytes32 key,
        uint256 size,
        uint256 collateral,
        uint256 averagePrice,
        int256 realisedPnl,
        uint256 insuranceLevel
    );

    event UpdatePnl(bytes32 key, bool hasProfit, uint256 delta);
    event CollectMarginFees(uint256 feeLP);

    modifier onlyAuthorized() {
        require(
            (msg.sender == router) || (msg.sender == orderbook),
            "Vault: invalid sender"
        );
        _;
    }

    // once the parameters are verified to be working correctly,
    // gov should be set to a timelock contract or a governance contract
    function initialize(
        address _LPToken,
        address _FeeLP,
        address _usdc,
        address _priceFeed,
        address _vaultUtil,
        uint256 _liquidationFee
    ) external {
        require(!isInitialized, "Vault: inited");
        isInitialized = true;
        gov = msg.sender;
        LPToken = _LPToken;
        FeeLP = _FeeLP;
        usdcToken = _usdc;
        priceFeed = _priceFeed;
        vaultUtil = IVaultUtil(_vaultUtil);
        liquidationFee = _liquidationFee;
        // 1 10%;2 20%;3 30%;4 40%;5 50%
        insuranceLevel[1] = 1000;
        insuranceLevel[2] = 2000;
        insuranceLevel[3] = 3000;
        insuranceLevel[4] = 4000;
        insuranceLevel[5] = 5000;

        maxLeverage = 100 * 10000;
        maxLiquidateLeverage = 1250 * 10000;
        LP_DECIMALS = 18;
        USDC_DECIMALS = 6;
        PRICE_DECIMALS = 30;
        inPrivateLiquidationMode = true;
        liquidationFeeRate = 100; //1%
        taxBasisPoints = 8; // base fee 0.08% for increase decrease
        minCollateral = 10e18; //10LP
        insuranceOdds = 20000; //insurance*2
        insuranceFeeRate = 300; //3%
        minProfitTime = 2 minutes;
        toTeamRatio = 2500;
    }

    function buyLP(
        address _receiver,
        uint256 _amount,
        uint256 _LPMinOut
    ) external nonReentrant returns (uint256) {
        require(LPFlag, "Vault: buy forbidden");
        _validateGasPrice();
        IERC20(usdcToken).safeTransferFrom(msg.sender, address(this), _amount);
        //get price first,u
        uint256 LPPrice = vaultUtil.getLPPrice();
        require(LPPrice > 0, "Vault: LP price 0");
        uint256 mintAmount = _amount
            .mul(10 ** LP_DECIMALS)
            .mul(10 ** PRICE_DECIMALS)
            .div(LPPrice)
            .div(10 ** USDC_DECIMALS);

        if (_LPMinOut > 0) {
            require(mintAmount >= _LPMinOut, "Vault: need more slippage");
        }

        ILPToken(LPToken).mintTo(_receiver, mintAmount);
        _updateTokenBalance(usdcToken);
        emit BuyLP(msg.sender, _receiver, usdcToken, _amount, mintAmount);

        return mintAmount;
    }

    function sellLP(
        address _receiver,
        uint256 _amount
    ) external nonReentrant returns (uint256) {
        require(LPFlag, "Vault: sell forbidden");
        _validateGasPrice();
        //how much usdc
        uint256 LPPrice = vaultUtil.getLPPrice();

        require(_amount > 0, "Vault: _amount 0");
        //transfer in,keep fee,burn left
        IERC20(LPToken).safeTransferFrom(msg.sender, address(this), _amount);

        //tokenBalances[LPToken] = tokenBalances[LPToken].sub(_amount);
        ILPToken(LPToken).burn(address(this), _amount);

        uint256 tokenAmount = _amount
            .mul(LPPrice)
            .mul(10 ** USDC_DECIMALS)
            .div(10 ** LP_DECIMALS)
            .div(10 ** PRICE_DECIMALS);

        //update tokenBalances in this func
        _transferOut(usdcToken, tokenAmount, _receiver);

        emit SellLP(msg.sender, _receiver, usdcToken, _amount, tokenAmount);

        return tokenAmount;
    }

    function increasePosition(
        address _account,
        address _indexToken,
        uint256 _sizeDelta,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _insuranceLevel, //0 1-5
        uint256 feeLP
    ) external nonReentrant onlyAuthorized {
        if (_insuranceLevel > 0) {
            require(
                insuranceLevel[_insuranceLevel] > 0,
                "Vault: insurance level invalid"
            );
        }
        require(
            _collateralDelta >= minCollateral,
            "Vault: less than min collateral"
        );
        _validateGasPrice();
        uint256 _insurance;
        if (_insuranceLevel > 0 && _sizeDelta > 0) {
            _insurance = _collateralDelta
                .mul(insuranceLevel[_insuranceLevel])
                .div(BASIS_POINTS_DIVISOR);
        }

        //burn insurance
        if (_insurance > 0) {
            ILPToken(LPToken).burn(address(this), _insurance);
        }

        require(
            whitelistedTokens[_indexToken],
            "Vault: index token not white listed"
        );

        uint256 price = _isLong
            ? getMaxPrice(_indexToken)
            : getMinPrice(_indexToken);

        //update global data first before update size
        UpdateGlobalDataParams memory p = UpdateGlobalDataParams(
            _account,
            _indexToken,
            _sizeDelta, //return directly when _sizeDelta is 0
            price,
            true,
            _isLong,
            _insuranceLevel,
            _insurance
        );
        vaultUtil.updateGlobalData(p);
        uint256 fee = getPositionFee(_sizeDelta);
        if (feeLP == 0) {
            feeReserves[LPToken] = feeReserves[LPToken].add(fee);
            splitLP(_account, fee);
        } else {
            feeReserves[FeeLP] = feeReserves[FeeLP].add(feeLP);
        }

        _increasePosition(
            _account,
            _indexToken,
            _sizeDelta,
            _collateralDelta,
            fee,
            _isLong,
            _insurance,
            _insuranceLevel
        );
    }

    function _increasePosition(
        address _account,
        address _indexToken,
        uint256 _sizeDelta,
        uint256 _collateralDelta,
        uint256 _fee,
        bool _isLong,
        uint256 _insurance,
        uint256 _insuranceLevel
    ) private {
        bytes32 key = getPositionKey(
            _account,
            _indexToken,
            _isLong,
            _insuranceLevel
        );
        Position storage position = positions[key];
        position.insurance = position.insurance.add(_insurance);
        uint256 orignLevel = position.collateral > 0
            ? position.size.mul(BASIS_POINTS_DIVISOR).div(position.collateral)
            : 0;
        uint256 price = _isLong
            ? getMaxPrice(_indexToken)
            : getMinPrice(_indexToken);
        if (position.size == 0) {
            position.averagePrice = price;
        }

        if (position.size > 0 && _sizeDelta > 0) {
            position.averagePrice = getNextAveragePrice(
                _indexToken,
                position.size,
                position.averagePrice,
                price,
                _sizeDelta
            );
        }

        position.collateral = position.collateral.add(_collateralDelta);
        require(position.collateral >= _fee, "Vault: less than margin fee");
        position.size = position.size.add(_sizeDelta);
        position.lastIncreasedTime = block.timestamp;

        require(position.size >= position.collateral, "Vault: size<collateral");

        if (position.size == _sizeDelta) {
            require(
                position.collateral.mul(maxLeverage) >=
                    position.size.mul(BASIS_POINTS_DIVISOR),
                "Vault: maxLeverage exceeded"
            );
        } else {
            validateLiquidation(
                _account,
                _indexToken,
                _isLong,
                true,
                _insuranceLevel
            );
        }

        vaultUtil.updateGlobal(
            _indexToken,
            price,
            _sizeDelta,
            _isLong,
            true,
            _insurance
        );

        emit IncreasePosition(
            _account,
            _indexToken,
            orignLevel,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            price,
            _fee,
            _insurance,
            _insuranceLevel
        );
        emit UpdatePosition(
            key,
            position.size,
            position.collateral,
            position.averagePrice,
            position.realisedPnl,
            price,
            _insuranceLevel
        );
    }

    function decreasePosition(
        address _account,
        address _indexToken,
        uint256 _sizeDelta,
        uint256 _collateralDelta,
        bool _isLong,
        address _receiver,
        uint256 _insuranceLevel,
        uint256 feeLP
    ) external nonReentrant onlyAuthorized returns (uint256, uint256) {
        if (_insuranceLevel > 0) {
            require(
                insuranceLevel[_insuranceLevel] > 0,
                "Vault: insurance level error"
            );
        }
        _validateGasPrice();
        uint256 price = _isLong
            ? getMinPrice(_indexToken)
            : getMaxPrice(_indexToken);
        uint256 insurance;
        {
            bytes32 key = getPositionKey(
                _account,
                _indexToken,
                _isLong,
                _insuranceLevel
            );
            Position storage position = positions[key];
            insurance = position.insurance;
            require(position.size > 0, "Vault: size 0");
            require(
                position.size >= _sizeDelta,
                "Vault: _sizeDelta bigger than size"
            );
        }

        //update global data first before update size
        UpdateGlobalDataParams memory p = UpdateGlobalDataParams(
            _account,
            _indexToken,
            _sizeDelta,
            price,
            false,
            _isLong,
            _insuranceLevel,
            insurance
        );
        vaultUtil.updateGlobalData(p);

        DecreasePositionParams memory param = DecreasePositionParams(
            _account,
            _indexToken,
            _sizeDelta,
            _collateralDelta,
            _isLong,
            _receiver,
            _insuranceLevel,
            feeLP
        );
        return _decreasePosition(param);
    }

    function _decreasePosition(
        DecreasePositionParams memory param
    ) private returns (uint256, uint256) {
        bytes32 key = getPositionKey(
            param.account,
            param.indexToken,
            param.isLong,
            param.insuranceLevel
        );
        Position storage position = positions[key];
        uint256 originalCollateral = position.collateral;
        FinalDecreasePositionParams
            memory finalParams = FinalDecreasePositionParams(
                param.account,
                param.receiver,
                false, //result.hasProfit,
                position.size.mul(BASIS_POINTS_DIVISOR).div(
                    position.collateral
                ), //orign level  *  10000
                0, //result.LPOut,
                0, //result.LPOutAfterFee,
                position.collateral,
                position.insurance,
                0, //result.profit,
                param.sizeDelta.mul(BASIS_POINTS_DIVISOR).div(position.size)
            );

        require(
            position.size >= param.sizeDelta,
            "Vault: _sizeDelta bigger than size"
        );
        require(
            position.collateral >= param.collateralDelta,
            "Vault: collateral delta bigger than collateral"
        );

        ReduceCollateralResult memory result = _reduceCollateral(
            param.account,
            param.indexToken,
            param.collateralDelta,
            param.sizeDelta,
            param.isLong,
            param.insuranceLevel,
            param.feeLP
        );

        finalParams.hasProfit = result.hasProfit;
        finalParams.LPOut = result.LPOut;
        finalParams.LPOutAfterFee = result.LPOutAfterFee;
        finalParams.profit = result.profit;

        param.collateralDelta = position.size == param.sizeDelta
            ? originalCollateral
            : param.collateralDelta;

        if (result.hasProfit) {
            //mint profit here,then transfer to user
            ILPToken(LPToken).mintTo(address(this), result.profit);
        } else {
            //burn loss
            ILPToken(LPToken).burn(address(this), result.profit);
        }
        uint256 price = param.isLong
            ? getMinPrice(param.indexToken)
            : getMaxPrice(param.indexToken);

        {
            if (position.size != param.sizeDelta) {
                position.size = position.size.sub(param.sizeDelta);
                require(
                    position.collateral >= minCollateral,
                    "Vault: less than min collateral"
                );
                require(
                    position.size >= position.collateral,
                    "Vault: size less than collateral"
                );

                validateLiquidation(
                    param.account,
                    param.indexToken,
                    param.isLong,
                    true,
                    param.insuranceLevel
                );
                emit UpdatePosition(
                    key,
                    position.size,
                    position.collateral,
                    position.averagePrice,
                    position.realisedPnl,
                    price,
                    param.insuranceLevel
                );
            } else {
                emit ClosePosition(
                    key,
                    position.size,
                    position.collateral,
                    position.averagePrice,
                    position.realisedPnl,
                    param.insuranceLevel
                );
                delete positions[key];
            }

            EmitPositionParams memory tp = EmitPositionParams(
                result.LPOut,
                result.LPOutAfterFee,
                result.feeLPAmount,
                param.account,
                param.indexToken,
                finalParams.orignLevel,
                param.collateralDelta,
                param.sizeDelta,
                param.isLong,
                price,
                position.insurance, //0 when close all size
                param.insuranceLevel,
                0
            );

            vaultUtil.updateGlobal(
                param.indexToken,
                price,
                param.sizeDelta,
                param.isLong,
                false,
                position.insurance
            );

            return (
                position.collateral,
                finalDecreasePosition(
                    finalParams,
                    position,
                    param.sizeDelta,
                    tp
                )
            );
        }
    }

    function emitPosition(EmitPositionParams memory t) private {
        uint256 fee = t.LPOut.sub(t.LPOutAfterFee);
        if (fee == 0) {
            fee = t.feeLPAmount;
            feeReserves[FeeLP] = feeReserves[FeeLP].add(fee);
        } else {
            splitLP(t.account, fee);
            feeReserves[LPToken] = feeReserves[LPToken].add(fee);
        }

        emit DecreasePosition(
            t.account,
            t.indexToken,
            t.orignLevel,
            t.collateralDelta,
            t.sizeDelta,
            t.isLong,
            t.price,
            fee,
            t.insurance,
            t.insuranceLevel,
            t.LPOutAfterFee,
            t.payInsurance
        );
    }

    function finalDecreasePosition(
        FinalDecreasePositionParams memory f,
        Position storage position,
        uint256 _sizeDelta,
        EmitPositionParams memory tp
    ) private returns (uint256) {
        //user have no profit,need pay insurance to user with odds
        if ((f.insurance > 0) && !f.hasProfit && _sizeDelta > 0) {
            //calculate profit or not,f.LPOut>f.collateral means user have profit
            require(f.LPOut <= f.collateral, "Vault: profit invalid");

            //already burn in up level func
            uint256 loss = f.profit;
            //by proportion
            uint256 payOdds = f
                .insurance
                .mul(f.insuranceProportion)
                .mul(insuranceOdds)
                .div(BASIS_POINTS_DIVISOR)
                .div(BASIS_POINTS_DIVISOR);
            //need pay user's insurance
            tp.payInsurance = loss > payOdds ? payOdds : loss;
            //mint insurance part
            if (tp.payInsurance > 0) {
                ILPToken(LPToken).mintTo(address(this), tp.payInsurance);
            }
            uint256 insuranceFee = tp.payInsurance.mul(insuranceFeeRate).div(
                BASIS_POINTS_DIVISOR
            );
            splitInsurance(insuranceFee);
            tp.payInsurance = tp.payInsurance.sub(insuranceFee);
        }

        emitPosition(tp);
        //already update tokenBalances in _transferOut
        if (f.LPOutAfterFee.add(tp.payInsurance) > 0) {
            _transferOut(
                LPToken,
                f.LPOutAfterFee.add(tp.payInsurance),
                f.receiver
            );
        }
        position.insurance = position
            .insurance
            .mul(BASIS_POINTS_DIVISOR.sub(f.insuranceProportion))
            .div(BASIS_POINTS_DIVISOR);
        return f.LPOutAfterFee.add(tp.payInsurance);
    }

    function liquidatePosition(
        address _account,
        address _indexToken,
        bool _isLong,
        address _feeReceiver,
        uint256 _insuranceLevel
    ) external nonReentrant {
        if (inPrivateLiquidationMode) {
            require(isLiquidator[msg.sender], "not liquidator");
        }

        bytes32 key = getPositionKey(
            _account,
            _indexToken,
            _isLong,
            _insuranceLevel
        );
        Position memory position = positions[key];
        require(position.size > 0, "Vault: size 0");
        (
            uint256 liquidationState,
            uint256 marginFeesLP,
            uint256 profitLP
        ) = validateLiquidation(
                _account,
                _indexToken,
                _isLong,
                false,
                _insuranceLevel
            );
        // state 0 normal;
        // 1 fee over collateral or collateral<loss,need liquidate;
        // 2 only decrease position
        require(liquidationState != 0, "Vault: state 0");
        if (liquidationState == 2) {
            DecreasePositionParams memory param = DecreasePositionParams(
                _account,
                _indexToken,
                position.size,
                0,
                _isLong,
                _account,
                _insuranceLevel,
                0
            );
            _decreasePosition(param);
            return;
        }

        feeReserves[LPToken] = feeReserves[LPToken].add(marginFeesLP);

        uint256 markPrice = _isLong
            ? getMinPrice(_indexToken)
            : getMaxPrice(_indexToken);

        vaultUtil.updateGlobal(
            _indexToken,
            markPrice,
            position.size,
            _isLong,
            false,
            position.insurance
        );

        //pay insurance
        uint256 payInsurance;
        if (position.insurance > 0) {
            uint256 maxPayAmount = position.insurance.mul(insuranceOdds).div(
                BASIS_POINTS_DIVISOR
            );
            payInsurance = profitLP > maxPayAmount ? maxPayAmount : profitLP;
            ILPToken(LPToken).mintTo(address(this), payInsurance);
            uint256 insuranceFee = payInsurance.mul(insuranceFeeRate).div(
                BASIS_POINTS_DIVISOR
            );
            splitInsurance(insuranceFee);
            payInsurance = payInsurance.sub(insuranceFee);
            IERC20(LPToken).safeTransfer(_account, payInsurance);
        }

        emit LiquidatePosition(
            _account,
            _indexToken,
            _isLong,
            position.size,
            position.collateral,
            position.realisedPnl,
            markPrice,
            _insuranceLevel,
            marginFeesLP + liquidationFee,
            payInsurance
        );

        delete positions[key];
        if (position.collateral > (marginFeesLP + liquidationFee)) {
            ILPToken(LPToken).burn(
                address(this),
                position.collateral.sub(marginFeesLP).sub(liquidationFee)
            );
        }
        _transferOut(LPToken, liquidationFee, _feeReceiver);

        splitLP(_account, marginFeesLP);
    }

    function splitLP(address user, uint256 amount) private {
        if (amount == 0) {
            return;
        }
        //to referral
        address referral = IRouter(router).referral();
        (address parent, ) = IReferral(referral).getUserParentInfo(user);
        (uint256 rate, ) = IReferral(referral).getTradeFeeRewardRate(user);
        uint256 userRewardAmount = amount.mul(rate).div(BASIS_POINTS_DIVISOR);
        uint256 parentRewardAmount = userRewardAmount;

        uint256 toTeamAmount = amount.mul(toTeamRatio).div(
            BASIS_POINTS_DIVISOR
        );
        uint256 left = amount.sub(toTeamAmount);
        toTeamAmount = toTeamAmount.sub(userRewardAmount).sub(
            parentRewardAmount
        );
        if(userRewardAmount.add(parentRewardAmount) > 0){
            IReferral(referral).updateLPClaimReward(
                user,
                parent,
                userRewardAmount,
                parentRewardAmount
            );
            IERC20(LPToken).safeTransfer(
                referral,
                userRewardAmount.add(parentRewardAmount)
            );
        }
        IERC20(LPToken).safeTransfer(teamAddress, toTeamAmount);

        IERC20(LPToken).safeTransfer(earnAddress, left);
    }

    function splitInsurance(uint256 amount) private {
        if (amount == 0) {
            return;
        }
        uint256 toTeamAmount = amount.mul(toTeamRatio).div(
            BASIS_POINTS_DIVISOR
        );
        uint256 left = amount.sub(toTeamAmount);
        IERC20(LPToken).safeTransfer(teamAddress, toTeamAmount);
        IERC20(LPToken).safeTransfer(earnAddress, left);
    }

    function getMaxPrice(address _token) public view returns (uint256) {
        if (_token == LPToken) {
            return vaultUtil.getLPPrice();
        }
        return IVaultPriceFeed(priceFeed).getPrice(_token, true);
    }

    function getMinPrice(address _token) public view returns (uint256) {
        if (_token == LPToken) {
            return vaultUtil.getLPPrice();
        }
        return IVaultPriceFeed(priceFeed).getPrice(_token, false);
    }

    function getPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _insuranceLevel
    )
        public
        view
        returns (uint256, uint256, uint256, uint256, bool, uint256, uint256)
    {
        bytes32 key = getPositionKey(
            _account,
            _indexToken,
            _isLong,
            _insuranceLevel
        );
        Position memory position = positions[key];
        uint256 realisedPnl = position.realisedPnl > 0
            ? uint256(position.realisedPnl)
            : uint256(-position.realisedPnl);
        return (
            position.size, // 0
            position.collateral, // 1
            position.averagePrice, // 2
            realisedPnl, // 3
            position.realisedPnl >= 0, // 4
            position.lastIncreasedTime, // 5
            position.insurance //6
        );
    }

    function getPositions(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _insuranceLevel
    ) public view returns (Position memory) {
        bytes32 key = getPositionKey(
            _account,
            _indexToken,
            _isLong,
            _insuranceLevel
        );

        return positions[key];
    }

    function getPositionsOfKey(
        bytes32 key
    ) public view returns (Position memory) {
        return positions[key];
    }

    function getPositionKey(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _insuranceLevel
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _account,
                    _indexToken,
                    _isLong,
                    _insuranceLevel
                )
            );
    }

    function getPositionLeverage(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _insuranceLevel
    ) public view returns (uint256) {
        bytes32 key = getPositionKey(
            _account,
            _indexToken,
            _isLong,
            _insuranceLevel
        );
        Position memory position = positions[key];
        require(position.collateral > 0, "Vault: collateral 0");
        return position.size.mul(BASIS_POINTS_DIVISOR).div(position.collateral);
    }

    function getNextAveragePrice(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        uint256 _nextPrice, //index token price current
        uint256 _sizeDelta
    ) public view returns (uint256) {
        require(
            whitelistedTokens[_indexToken],
            "Vault: getNextAveragePrice index token not white listed"
        );
        if (_size == 0) {
            return _nextPrice;
        }

        uint256 pricePrecision = 10 ** PRICE_DECIMALS;
        uint256 sum = _size.mul(pricePrecision).div(_averagePrice).add(
            _sizeDelta.mul(pricePrecision).div(_nextPrice)
        );
        return _size.add(_sizeDelta).mul(pricePrecision).div(sum);
    }

    function getProfitLP(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _lastIncreasedTime
    ) public view returns (bool, uint256) {
        if (_averagePrice == 0 || _size == 0) {
            return (false, 0);
        }

        uint256 price = _isLong
            ? getMinPrice(_indexToken)
            : getMaxPrice(_indexToken);
        uint256 priceDelta = _averagePrice > price
            ? _averagePrice.sub(price)
            : price.sub(_averagePrice);
        uint256 profit = _size.mul(priceDelta).div(_averagePrice);
        bool hasProfit;

        if (_isLong) {
            hasProfit = price > _averagePrice;
        } else {
            hasProfit = _averagePrice > price;
        }

        uint256 minBps = block.timestamp > _lastIncreasedTime.add(minProfitTime)
            ? 0
            : minProfitBasisPoints[_indexToken];
        if (
            hasProfit && profit.mul(BASIS_POINTS_DIVISOR) <= _size.mul(minBps)
        ) {
            profit = 0;
        }
        return (hasProfit, profit);
    }

    function getPositionFee(uint256 _sizeDelta) public view returns (uint256) {
        if (_sizeDelta == 0) {
            return 0;
        }
        require(BASIS_POINTS_DIVISOR > 0, "BASIS_POINTS_DIVISOR 0");
        uint256 afterFee = _sizeDelta
            .mul(BASIS_POINTS_DIVISOR.sub(taxBasisPoints))
            .div(BASIS_POINTS_DIVISOR);
        return _sizeDelta.sub(afterFee);
    }

    function _reduceCollateral(
        address _account,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _insuranceLevel,
        uint256 _feeLP
    ) private returns (ReduceCollateralResult memory r) {
        bytes32 key = getPositionKey(
            _account,
            _indexToken,
            _isLong,
            _insuranceLevel
        );
        Position storage position = positions[key];
        //return fee base on LP token and update feeReserve
        uint256 fee = _collectMarginFees(_sizeDelta);
        if (_feeLP >= fee) {
            fee = 0;
        }
        r.feeLPAmount = _feeLP;

        bool hasProfit;
        uint256 adjustedDelta;

        {
            (bool _hasProfit, uint256 delta) = getProfitLP(
                _indexToken,
                position.size,
                position.averagePrice,
                _isLong,
                position.lastIncreasedTime
            );
            hasProfit = _hasProfit;
            require(position.size > 0, "Vault: size 0 _reduceCollateral");
            adjustedDelta = _sizeDelta.mul(delta).div(position.size);
        }
        r.profit = adjustedDelta;
        uint256 LPOut;

        if (position.size == _sizeDelta) {
            LPOut = LPOut.add(position.collateral);
            position.collateral = 0;
        } else {
            LPOut = LPOut.add(_collateralDelta);
            //position reduce collateral
            require(
                position.collateral >= _collateralDelta,
                "Vault: collateral<_collateralDelta"
            );
            position.collateral = position.collateral.sub(_collateralDelta);
        }

        if (hasProfit) {
            LPOut = LPOut.add(adjustedDelta);
            position.realisedPnl = position.realisedPnl + int256(adjustedDelta);
        } else {
            position.realisedPnl = position.realisedPnl - int256(adjustedDelta);
            if (LPOut > adjustedDelta) {
                LPOut = LPOut.sub(adjustedDelta);
            } else {
                position.collateral = position.collateral.sub(adjustedDelta);
            }
        }

        uint256 LPOutAfterFee = LPOut;
        if (LPOut > fee) {
            LPOutAfterFee = LPOut.sub(fee);
        } else {
            position.collateral = position.collateral.sub(fee);
        }

        emit UpdatePnl(key, hasProfit, adjustedDelta);
        r.hasProfit = hasProfit;

        r.LPOut = LPOut;
        r.LPOutAfterFee = LPOutAfterFee;
    }

    // return fee LP and update feeReserve
    function _collectMarginFees(uint256 _sizeDelta) private returns (uint256) {
        uint256 feeLP = getPositionFee(_sizeDelta);
        feeReserves[LPToken] = feeReserves[LPToken].add(feeLP);
        emit CollectMarginFees(feeLP);
        return feeLP;
    }

    function _transferIn(address _token) private returns (uint256) {
        uint256 prevBalance = tokenBalances[_token];
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        tokenBalances[_token] = nextBalance;

        return nextBalance.sub(prevBalance);
    }

    function _transferOut(
        address _token,
        uint256 _amount,
        address _receiver
    ) private {
        IERC20(_token).safeTransfer(_receiver, _amount);
        tokenBalances[_token] = IERC20(_token).balanceOf(address(this));
    }

    function _updateTokenBalance(address _token) private {
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        tokenBalances[_token] = nextBalance;
    }

    // we have this validation as a function instead of a modifier to reduce contract size
    function _onlyGov() private view {
        require(msg.sender == gov, "not gov");
    }

    // we have this validation as a function instead of a modifier to reduce contract size
    function _validateGasPrice() private view {
        if (maxGasPrice == 0) {
            return;
        }
        require(tx.gasprice <= maxGasPrice, "Vault: maxGasPrice exceeded");
    }

    //state 0 normal;
    // 1 fee over collateral or collateral<loss;
    // 2 over max leverage,need decrease position
    function validateLiquidation(
        address _account,
        address _indexToken,
        bool _isLong,
        bool _raise,
        uint256 _insuranceLevel
    ) public view returns (uint256, uint256, uint256) {
        bytes32 key = getPositionKey(
            _account,
            _indexToken,
            _isLong,
            _insuranceLevel
        );
        Position memory position = positions[key];
        require(position.size > 0, "Vault: key not exist");

        (bool hasProfit, uint256 profitLP) = getProfitLP(
            _indexToken,
            position.size,
            position.averagePrice,
            _isLong,
            position.lastIncreasedTime
        );

        uint256 marginFees = getPositionFee(position.size);
        if (!hasProfit && position.collateral < profitLP) {
            if (_raise) {
                revert("Vault: losses exceed collateral");
            }
            return (1, marginFees, profitLP);
        }

        uint256 remainingCollateral = position.collateral;

        if (!hasProfit) {
            remainingCollateral = position.collateral.sub(profitLP);
        }

        if (remainingCollateral < marginFees) {
            if (_raise) {
                revert("Vault: marginFees exceed collateral");
            }
            // cap the fees to the remainingCollateral
            return (1, remainingCollateral, profitLP);
        }

        if (remainingCollateral < marginFees.add(liquidationFee)) {
            if (_raise) {
                revert("Vault: liquidation fees exceed collateral");
            }
            return (1, marginFees, profitLP);
        }

        //remainingCollateral*maxLiquidateLeverage<=position.size
        if (
            remainingCollateral.mul(maxLiquidateLeverage) <=
            position.size.mul(BASIS_POINTS_DIVISOR)
        ) {
            if (_raise) {
                revert("Vault: maxLeverage exceeded");
            }
            return (2, marginFees, profitLP);
        }

        return (0, marginFees, profitLP);
    }

    function allWhitelistedTokensLength() external view returns (uint256) {
        return allWhitelistedTokens.length;
    }

    function setInPrivateLiquidationMode(
        bool _inPrivateLiquidationMode
    ) external {
        _onlyGov();
        inPrivateLiquidationMode = _inPrivateLiquidationMode;
    }

    function setLiquidator(address _liquidator, bool _isActive) external {
        _onlyGov();
        isLiquidator[_liquidator] = _isActive;
    }

    function setMaxGasPrice(uint256 _maxGasPrice) external {
        _onlyGov();
        maxGasPrice = _maxGasPrice;
    }

    function setGov(address _gov) external {
        _onlyGov();
        gov = _gov;
    }

    function setRouterOrderbook(address _router, address _orderbook) external {
        _onlyGov();
        router = _router;
        orderbook = _orderbook;
    }

    function setPriceFeed(address _priceFeed) external {
        _onlyGov();
        priceFeed = _priceFeed;
    }

    function setMaxLeverage(uint256 _maxLeverage) external {
        _onlyGov();
        require(_maxLeverage > MIN_LEVERAGE, "less than min Leverage");
        maxLeverage = _maxLeverage;
    }

    function setMaxLiquidateLeverage(uint256 _maxLiquidateLeverage) external {
        _onlyGov();
        require(_maxLiquidateLeverage > MIN_LEVERAGE, "less than min Leverage");
        maxLiquidateLeverage = _maxLiquidateLeverage;
    }

    function setFees(
        uint256 _taxBasisPoints,
        uint256 _liquidationFeeRate,
        uint256 _minProfitTime,
        uint256 _liquidationFee
    ) external {
        _onlyGov();
        require(_taxBasisPoints <= MAX_FEE_BASIS_POINTS, "tax fee");
        taxBasisPoints = _taxBasisPoints;
        liquidationFeeRate = _liquidationFeeRate;
        minProfitTime = _minProfitTime;
        liquidationFee = _liquidationFee;
    }

    //set for every token
    function setTokenConfig(
        address _token,
        uint256 _tokenDecimals,
        uint256 _minProfitBps
    ) external {
        _onlyGov();
        // increment token count for the first time
        if (!whitelistedTokens[_token]) {
            allWhitelistedTokens.push(_token);
        }

        whitelistedTokens[_token] = true;
        tokenDecimals[_token] = _tokenDecimals;
        minProfitBasisPoints[_token] = _minProfitBps;
        // validate price feed
        getMaxPrice(_token);
    }

    function setInsuranceLevel(
        uint256[] calldata _type,
        uint256[] calldata _rate
    ) external {
        _onlyGov();
        require(_type.length == _rate.length, "Vault: len not equal");
        for (uint256 i; i < _type.length; i++) {
            insuranceLevel[_type[i]] = _rate[i];
        }
    }

    function clearTokenConfig(address _token) external {
        _onlyGov();

        require(whitelistedTokens[_token], "white listed");
        delete whitelistedTokens[_token];
        delete tokenDecimals[_token];
        delete minProfitBasisPoints[_token];
    }

    function withdrawFees(
        address _token,
        address _receiver
    ) external returns (uint256) {
        _onlyGov();
        uint256 amount = feeReserves[_token];
        if (amount == 0) {
            return 0;
        }
        feeReserves[_token] = 0;
        _transferOut(_token, amount, _receiver);
        return amount;
    }

    // the governance controlling this function should have a timelock
    function migrateVault(
        address _newVault,
        address _token,
        uint256 _amount
    ) external {
        _onlyGov();
        IERC20(_token).safeTransfer(_newVault, _amount);
    }

    function setDecimal(uint256 LPDecimal, uint256 usdcDecimal) external {
        _onlyGov();
        LP_DECIMALS = LPDecimal;
        USDC_DECIMALS = usdcDecimal;
    }

    function setMinCollateral(uint256 _minCollateral) external {
        _onlyGov();
        minCollateral = _minCollateral;
    }

    function subFeeReserves(uint256 _subAmount, address _token) external {
        _onlyGov();
        feeReserves[_token] = feeReserves[_token].sub(_subAmount);
    }

    function setSplitFeeParams(
        address _teamAddress,
        address _earnAddress,
        uint256 _toTeamRatio
    ) external {
        _onlyGov();
        teamAddress = _teamAddress;
        earnAddress = _earnAddress;
        toTeamRatio = _toTeamRatio;
    }

    function setLPToken(
        address _LPToken,
        address _FeeLP,
        address _usdc,
        IVaultUtil _vaultUtil
    ) external {
        _onlyGov();
        LPToken = _LPToken;
        FeeLP = _FeeLP;
        usdcToken = _usdc;
        vaultUtil = _vaultUtil;
    }

    function setInsurance(
        uint256 _insuranceOdds,
        uint256 _insuranceFeeRate
    ) external {
        _onlyGov();
        insuranceOdds = _insuranceOdds;
        insuranceFeeRate = _insuranceFeeRate;
    }

    function setLPFlag(bool _LPFlag) external {
        _onlyGov();
        LPFlag = _LPFlag;
    }

    function adjustForDecimals(
        uint256 _amount,
        address _tokenFrom,
        address _tokenTo
    ) public view returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        uint256 decimalsDiv;
        uint256 decimalsMul;
        if (_tokenFrom == LPToken) {
            decimalsDiv = LP_DECIMALS;
        } else if (_tokenFrom == usdcToken) {
            decimalsDiv = USDC_DECIMALS;
        } else {
            decimalsDiv = tokenDecimals[_tokenFrom];
        }

        if (_tokenTo == LPToken) {
            decimalsMul = LP_DECIMALS;
        } else if (_tokenTo == usdcToken) {
            decimalsMul = USDC_DECIMALS;
        } else {
            decimalsMul = tokenDecimals[_tokenTo];
        }
        return _amount.mul(10 ** decimalsMul).div(10 ** decimalsDiv);
    }
}

