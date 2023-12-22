// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// system
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./Initializable.sol";

// interfaces
import "./ITreasury.sol";
import "./IAccessContract.sol";
import "./IFormulas.sol";
import "./IBlxToken.sol";
import "./IStakingContract.sol";
import "./IBlxStaking.sol";
import "./IRewardsDistributionRecipient.sol";

// libs
import {OptionLib} from "./OptionLib.sol";
import {HistoryVolatility} from "./HistoryVolatility.sol";
import {Abdk} from "./AbdkUtil.sol";
import {ABDKMath64x64} from "./ABDKMath64x64.sol";

// logs
import "./console.sol";


contract Treasury is ITreasury, AccessContract, Initializable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBlxToken;
    using Abdk for uint;
    using ABDKMath64x64 for int128;

    event BlxBurned(address user, uint256 amount);

    IERC20 USD;
    IBlxToken BLX;

    IStakingContract staking;
    IBlxStaking blxStaking;
    IFormulas formulas;

    // --- begin of asymmetry info ----

    // total locked collateral value
    uint public lockedCollateral;

    // divisor to control max acceptable trade size(in terms of collateral required not premium received)
    uint public tradeSizeDivisor = 10;

    // product type => derivative id => info struct
    mapping(uint=>mapping(uint=>AsymmetryInfo)) putCallOptions;
    // product type => derivative id => total collateral
    mapping(uint=>mapping(uint=>uint)) isotropicOptions;

    // --- end of asymmetry info ----

    // platform income, subject to fees
    mapping(address => uint) public totalIncome;
    // amount of tokens to keep above lockedCollateral: token => gap amount
    mapping(address => uint) public gapAmount;
    // own platform income, which can be withdrawn: token => (wallet => amount)
    mapping(address => mapping (address => uint)) public platformOwnIncome;
    
    uint public blxStakingReward; // reward attributed to BLX staking pool

    uint public lostUsd; // lost usd is part of own income
    uint public lostBlx; // lost blx is part of own income

    struct Balance {
        uint investments;
        uint payouts;
    }

    mapping(address => mapping(OptionLib.ProductKind => Balance)) balances;

    mapping(address => bool) private _isOperator;

    modifier onlyOperator() {
        require(_isOperator[_msgSender()], "TR:CALLER_NOT_ALLOWED");
        _;
    }

    modifier onlyValidToken(address token) {
        require(token == address(USD) || token == address(BLX),
            "TR:UNSUPPORTED_TOKEN"
        );
        _;
    }

    modifier onlyValidProduct(OptionLib.ProductKind product) {
        require(
            OptionLib.isValidProduct(product),
            "TR:UNSUPPORTED_PRODUCT"
        );
        _;
    }

    // ============= OPERATOR ===============

    function isOperator(address _operator) public view returns (bool) {
        return _isOperator[_operator];
    }

    function allowOperator(address _operator) public onlyOwner {
        require(_operator != address(0), "TR:ZERO_ADDRESS");
        _isOperator[_operator] = true;
    }

    function removeOperator(address _operator) public onlyOwner {
        require(_operator != address(0), "TR:ZERO_ADDRESS");
        delete _isOperator[_operator];
    }

    function _updateBalance(
        address token,
        uint investment,
        uint payout,
        OptionLib.ProductKind product
    ) internal
        onlyValidToken(token)
        onlyValidProduct(product)
    {
        balances[token][product].investments += investment;
        balances[token][product].payouts += payout;
        //console.log("receive %d", investment);
        //console.log("pay %d", payout);
        distributeGainLoss();
    }

    function getDigitalBalances(address token)
        public view
        returns (uint investments, uint payouts)
    {
        Balance memory balance =
            balances[token][OptionLib.ProductKind.Digital];
        return (balance.investments, balance.payouts);
    }

    function getAmericanBalances(address token)
        public view
        returns (uint investments, uint payouts)
    {
        Balance memory balance =
            balances[token][OptionLib.ProductKind.American];
        return (balance.investments, balance.payouts);
    }

    function getTurboBalances(address token)
        public view
        returns (uint investments, uint payouts)
    {
        Balance memory balance =
            balances[token][OptionLib.ProductKind.Turbo];
        return (balance.investments, balance.payouts);
    }

    function _cut(uint a, uint b)
        internal pure returns (uint)
    {
        return a > b ? a - b : 0;
    }

    function getPlatformProfits(address token)
        public view
        returns (uint digital, uint american, uint turbo)
    {
        {
            (uint i, uint p) = getDigitalBalances(token);
            digital = _cut(i, p);
        }
        {
            (uint i, uint p) = getAmericanBalances(token);
            american = _cut(i, p);
        }
        {
            (uint i, uint p) = getTurboBalances(token);
            turbo = _cut(i, p);
        }
    }

    function getPlatformLoss(address token)
        public view
        returns (uint digital, uint american, uint turbo)
    {
        {
            (uint i, uint p) = getDigitalBalances(token);
            digital = _cut(p, i);
        }
        {
            (uint i, uint p) = getAmericanBalances(token);
            american = _cut(p, i);
        }
        {
            (uint i, uint p) = getTurboBalances(token);
            turbo = _cut(p, i);
        }
    }

    function registerBalanceChange(
        address token,
        uint investment,
        uint payout,
        OptionLib.ProductKind product
    ) external override
        onlyTrustedCaller
    {
        _updateBalance(token, investment, payout, product);
    }

    ///@dev USDC reward payment is treated as 'loss'
    function registerRewardPaid(
        uint amount
    ) external override
        onlyTrustedCaller
    {
        IStakingContract(staking)
            .notifyStakingLossAmount(amount);
    }

    ///@dev burn received BLX fee
    function burnBlxFee(
        uint amount
    ) external override
        onlyTrustedCaller
    {
        BLX.transfer(burner, amount);
        emit BlxBurned(address(this), amount);
    }


    // platform income recipient, owner by default
    address public platformBeneficiary1;
    address public platformBeneficiary2;

    // period between distributions
    uint distributionPeriod;
    uint lastDistributeDate;

    // burner address
    address public burner;

    constructor(address _usdToken, address _blxToken, address _burner)
    {
        require(_usdToken != address(0), "TR:USDC_ZERO_ADDRESS");
        require(_blxToken != address(0), "TR:BLX_ZERO_ADDRESS");
        require(_burner != address(0), "TR:BURNER_ZERO_ADDRESS");

        distributionPeriod = 7 days;

        USD = IERC20(_usdToken);
        BLX = IBlxToken(_blxToken);
        burner = _burner;
        platformBeneficiary1 = 0xa0D00b87739ec1dF412Ffe030E12d4387D3CB686;
        platformBeneficiary2 = 0xBc6Fc8C26d4AB5DD1b9DB1651F394303446e04A0;
    } 

    function configure(address _staking, address _formulas, address _blxStaking)
        external onlyOwner initializer
    {
        require(_staking  != address(0), "TR:STAKING_ZERO_ADDRESS");
        require(_formulas != address(0), "TR:FORMULAS_ZERO_ADDRESS");
        require(_blxStaking  != address(0), "TR:BLX_STAKING_ZERO_ADDRESS");

        //        gapAmount[_usdToken] = 0;
        //        gapAmount[_blxToken] = 0;

        staking = IStakingContract(_staking);
        blxStaking = IBlxStaking(_blxStaking);
        formulas = IFormulas(_formulas);

        try staking.getTotalUsdStake() {

        }
        catch {
            revert("TR:STAKING_ADDRESS_BAD");
        }

        try blxStaking.getTotalStake() {

        }
        catch {
            revert("TR:BLX_STAKING_ADDRESS_BAD");
        }

        try formulas.volatilityFactor() {

        }
        catch {
            revert("TR:FORMULAS_ADDRESS_BAD");
        }
    }

    /// @dev set new platform own income beneficiary
    function setPlatformBeneficiary(address _beneficiary)
        external 
    {
        require(_beneficiary != address(0), "Beneficiary cannot be zero address");
        if (msg.sender == platformBeneficiary1)
            platformBeneficiary1 = _beneficiary;
        else if (msg.sender == platformBeneficiary2)
            platformBeneficiary2 = _beneficiary;
        else
            revert("Not platform beneficiary");
    }

    function setGapAmounts(uint usdGap, uint blxGap)
        external onlyOwner
    {
        gapAmount[address(USD)] = usdGap;
        gapAmount[address(BLX)] = blxGap;
    }

    modifier beneficiaryOnly(address caller) {
        require(
            platformBeneficiary1 == caller || platformBeneficiary2 == caller,
            "only platform beneficiary can call"
        );
        _;
    }

    enum RewardToken {USD_TOKEN, BLX_TOKEN}

    function tokenByType(RewardToken tokenType) internal view returns(address) {
        address token;
        if (tokenType == RewardToken.USD_TOKEN) {
            token = address(USD);
        } else if (tokenType == RewardToken.BLX_TOKEN) {
            token = address(BLX);
        } else {
            revert("token kind not supported");
        }

        return token;
    }

    /// @dev sendout platform beneficiary income
    /// can be called by anyone as beneificary is fixed
    function distriutePlatformOwnIncome(RewardToken rewardToken, uint amount, address beneficiary) 
        public beneficiaryOnly(beneficiary)
    {
        address token = tokenByType(rewardToken);
        uint gap = gapAmount[token];
        uint g2 = gap * 125 / 1000;
        uint g1 = gap - g2;
        require(
            platformOwnIncome[token][beneficiary] >= amount + (beneficiary == platformBeneficiary1 ? g1 : g2),
            "TR:NOT_ENOUGH_GAP"
        );
        uint requiredCollateral = lockedCollateral;

        // if platform income has been locked for collateral(before it is realized), wait until they are unlocked.
        require(
            address(token) != address(USD) ||
            USD.balanceOf(address(this)) >= requiredCollateral 
                + amount, 
            requiredCollateral > 0 ? "TR:NOT_ENOUGH_COLLATERAL" : "TR:NOT_ENOUGH_BALANCE" 
        );
        
        _payTokensTo(IERC20(token), beneficiary, amount);
        platformOwnIncome[token][beneficiary] -= amount;
    }

    /// @dev withdraw platform own income
    function withdrawPlatformOwnIncome(RewardToken rewardToken, uint amount)
        external beneficiaryOnly(_msgSender())
    {
        distriutePlatformOwnIncome(rewardToken, amount, _msgSender());
    }

    /// @dev distribute all beneficiary income
    function distributePlatformIncome()
        external 
    {
        address token = tokenByType(RewardToken.USD_TOKEN);
        require(totalBeneficiaryIncome() > 0, "TR:NOTHING_TO_DISTRIBUTE");
        uint amount = platformOwnIncome[token][platformBeneficiary2];
        if (amount > 0) distriutePlatformOwnIncome(RewardToken.USD_TOKEN, amount, platformBeneficiary2);
        amount = platformOwnIncome[token][platformBeneficiary1];
        if (amount > 0) distriutePlatformOwnIncome(RewardToken.USD_TOKEN, amount, platformBeneficiary1);
    }

    /// @dev distribute abeneficiary income
    function distributeBeneficiaryIncome(address beneficiary)
        external 
    {
        address token = tokenByType(RewardToken.USD_TOKEN);
        distriutePlatformOwnIncome(RewardToken.USD_TOKEN, platformOwnIncome[token][beneficiary], beneficiary);
    }

    /**
     * @dev lockBetCollateral - locks collateral for specified parameters
     * @param amount collateral amount to lock
     * @param derivativeId derivative id
     * @param product option product type
     * @param optionType option type: PUT or CALL if applicable, OptionLib.OptionTypeNA otherwise
     */
    function lockBetCollateral(
        uint amount,
        uint derivativeId,
        uint product,
        uint optionType
    )
    external override onlyTrustedCaller
    {
        uint collateralAfterUpdate = lockedCollateral + amount;
        uint myBalance = USD.balanceOf(address(this));
        // TODO: ensure that collateral is less than free funds

        // looks wrong, disable for now
        //        if (_amount > poolHelp / historyVolatility.getCountDerivative() / 1000) {
        //            collateral = poolHelp / historyVolatility.getCountDerivative() / 1000;
        //        }
        //console.log("usdc = %d", myBalance );
        //console.log("colllateral locked = %d", lockedCollateral);
        //console.log("colllateral = %d", amount);
        require(
            myBalance >= collateralAfterUpdate 
                // exclude platform income balance and blxStaking reward from participating as collateral
                + platformOwnIncome[address(USD)][platformBeneficiary1] 
                + platformOwnIncome[address(USD)][platformBeneficiary1]
                + blxStakingReward,
            "TR:TOO_MUCH_COLLATERAL_LOCKED"
        );

        // collaternal < available/tradSizeDivisor
        // where available exclude platform income and blx staking reward
        require(
            amount * tradeSizeDivisor 
            + lockedCollateral
            + platformOwnIncome[address(USD)][platformBeneficiary1] 
            + platformOwnIncome[address(USD)][platformBeneficiary1]
            + blxStakingReward
            <= myBalance,
            "TR:COLLATERAL_TOO_LARGE"
        );

        lockedCollateral = collateralAfterUpdate;

        uint productCollateral = getCollateralByOptionType(product, derivativeId, optionType);
        updateCollateralByOptionType(product, derivativeId, optionType, productCollateral + amount);

        // TODO: implement risk accounting (new scope)
    }

    /**
     * @dev function unlockBetCollateral - unlocks collateral for specified parameters
     * @param amount collateral amount to lock
     * @param derivativeId derivative id
     * @param product option product type
     * @param optionType option type: PUT or CALL if applicable, OptionLib.OptionTypeNA otherwise
     */
    function unlockBetCollateral(
        uint amount,
        uint derivativeId,
        uint product,
        uint optionType
    ) external override onlyTrustedCaller
    {
        require(lockedCollateral >= amount, "TR:CANNOT_FREE_COLLATERAL_AMOUNT");
        lockedCollateral -= amount;

        uint productCollateral = getCollateralByOptionType(product, derivativeId, optionType);
        updateCollateralByOptionType(product, derivativeId, optionType, productCollateral - amount);

        // TODO: implement risk accounting (new scope)
    }

    /// @dev returns total collateral value for provided product and derivative
    /// @param product option product type
    /// @param derivativeId derivative id
    /// @return total collateral value
    function totalCollateral(uint product, uint derivativeId) public view override returns(uint) {
        if (OptionLib.isProductCallPutType(product)) {
            AsymmetryInfo memory info = putCallOptions[product][derivativeId];
            return info.callCollateral + info.putCollateral;
        }

        return isotropicOptions[product][derivativeId];
    }

    /// @dev returns total collateral avaiable for trade
    /// @return total collateral value available including new bet amount
    function avaiableCollateral() public view returns(int) {
        // lose 1 bit for sign but assume would never happen as even 18(~60 bits) decimal number would
        // mean 64 bit whole number which is almost impossible for collateral pool size
        // let alone 6 decimal for USDC/USDT
        // this should not be -ve !   
        return int(USD.balanceOf(address(this))) 
                    - int(lockedCollateral) 
                    - int(platformOwnIncome[address(USD)][platformBeneficiary1]) 
                    - int(platformOwnIncome[address(USD)][platformBeneficiary2]);
    }

    /// @dev returns available beneficiary income
    function beneficiaryIncome(address beneficiary) public view returns(uint) {
        return platformOwnIncome[address(USD)][beneficiary];
    }
    /// @dev returns total available beneficiary income
    function totalBeneficiaryIncome() public view returns(uint) {
        return 
        platformOwnIncome[address(USD)][platformBeneficiary1]
        +
        platformOwnIncome[address(USD)][platformBeneficiary2];
    }

    /// @dev returns total platform income(obligation including blx staking)
    function platformIncome() public view returns(uint)
    {
        return blxStakingReward + totalBeneficiaryIncome();
    }

    /// @dev returns collaterall value by option type
    /// @param product option product type
    /// @param derivativeId derivative id
    /// @param optionType option type: call/put/na
    /// @return collateral value
    function getCollateralByOptionType(uint product, uint derivativeId, uint optionType)
    public view override returns(uint)
    {
        if (OptionLib.isProductCallPutType(product)) {
            AsymmetryInfo memory info = putCallOptions[product][derivativeId];
            if (optionType == OptionLib.OPTION_TYPE_CALL)
                return info.callCollateral;
            else
                return info.putCollateral;
        }

        return isotropicOptions[product][derivativeId];
    }

    /// @dev sets new collateral value by option type
    /// @param product option product type
    /// @param derivativeId derivative id
    /// @param optionType option type: call/put/na
    /// @param amount new collateral value
    function updateCollateralByOptionType(
        uint product,
        uint derivativeId,
        uint optionType,
        uint amount
    )
    internal
    {
        if (OptionLib.isProductCallPutType(product)) {
            AsymmetryInfo storage info = putCallOptions[product][derivativeId];
            if (optionType == OptionLib.OPTION_TYPE_CALL)
                info.callCollateral = amount;
            else
                info.putCollateral = amount;
        }

        isotropicOptions[product][derivativeId] = amount;
    }

    /// @dev get first Adjustment Coefficient
    /// @param product option product type
    /// @param derivativeId derivative id
    /// @param optionType option type: call/put/na
    function get_r1(uint product, uint derivativeId, uint optionType)
    public view override returns (int128 r1)
    {
        require(OptionLib.isValidOptionType(optionType), "STR:INVALID_OPTION_TYPE");

        if (optionType == OptionLib.OPTION_TYPE_NA) {
            return Abdk._1;
        }

        AsymmetryInfo memory info = putCallOptions[product][derivativeId];
        uint l = totalCollateral(product, derivativeId);
        if (l == 0) {
            // no collateral yet
            return Abdk._1;
        }

        uint k;
        if (optionType == OptionLib.OPTION_TYPE_CALL) {
            k = info.callCollateral;
        } else if (optionType == OptionLib.OPTION_TYPE_PUT) {
            k = info.putCollateral;
        }
        // no other options

        //console.log("contract k: ", k);
        //console.log("contract l: ", l);
        r1 = k.toAbdk().div(l.toAbdk());
    }

    /// @dev get second Adjustment Coefficient
    /// @param product option product type
    /// @param derivativeId derivative id
    function get_r2(uint product, uint derivativeId)
    public view override returns(int128 r2)
    {
        uint totalStake = staking.getTotalUsdStake();
        require(totalStake != 0, "STR:NO_STAKE_CANT_CALC");
        //console.log("totalStake = %d", totalStake);
        r2 = totalCollateral(product, derivativeId).toAbdk()
        .div(totalStake.toAbdk());
    }

    /// @dev calculates adjustment coefficient for product & derivative
    /// @param product option product type
    /// @param derivativeId derivative id
    /// @param optionType option type: call/put/na
    function adjCoeff(uint product, uint derivativeId, uint optionType)
    public view override returns(int128 coef)
    {
        int128 r2 = get_r2(product, derivativeId);
        int128 r1 = get_r1(product, derivativeId, optionType);
        coef = formulas.adj_coef(r1, r2);
    }

    /// @dev calculates maximum trade size(in USD)
    function maxTradeSize()
    public view returns(uint256)
    {
        return (USD.balanceOf(address(this)) 
                - lockedCollateral
                - blxStakingReward
                - platformOwnIncome[address(USD)][platformBeneficiary1] 
                - platformOwnIncome[address(USD)][platformBeneficiary2]
                )
                /tradeSizeDivisor;
    }

    function payBlxTo(address _to, uint _amount)
    public override onlyTrustedCaller
    {
        _payTokensTo(BLX, _to, _amount);
    }

    function takeBlxFrom(address _from, uint _amount)
    external override onlyTrustedCaller
    {
        require(_amount > 0, "TR:PAY_ZERO_AMOUNT");
        _takeTokensFrom(BLX, _from, _amount);
    }

    function setSizeDivisor(uint n)
    external onlyOperator
    {
        require(n > 0, "TR:DIVISOR_ZERO_AMOUNT");
        tradeSizeDivisor = n;
    }

    function payTokensTo(address _to, uint _amount)
    external override onlyTrustedCaller
    {
        require(_amount > 0, "TR:PAY_ZERO_AMOUNT");
        address sender = _msgSender();
        if (sender == address(staking) || sender == address(blxStaking)) {
            uint requiredCollateral = lockedCollateral;
            uint _platformIncome = totalBeneficiaryIncome();
            //console.log("locked %d", lockedCollateral);
            // staker can only withdraw 'excess' lpool amount
            // (enough collateral to pay for loss)
            // platform income is not part of the LPool but is kept under treasury
            // blxStakingReward is also not used for collateral
            require(sender != address(blxStaking) || _amount <= blxStakingReward, "TR:NOT_ENOUGH_BLX_REWARD");
            require(
                USD.balanceOf(address(this)) 
                + (sender == address(blxStaking) ? _amount : 0) 
                >= requiredCollateral 
                    + _amount 
                    + blxStakingReward
                    // blx staking can front run platform in withdraw
                    + (sender != address(blxStaking) ? _platformIncome : 0),
                requiredCollateral > 0 ? "TR:NOT_ENOUGH_COLLATERAL" : "TR:NOT_ENOUGH_BALANCE"
            );
        }
        if (sender == address(blxStaking)) {
            // portion of 'locked' reward reduced(claimed)
            blxStakingReward -= _amount;
        }
        _payTokensTo(USD, _to, _amount);
    }

    /// @dev withdraws and burns specified amounts
    function withdrawBlx(address user, uint withdrawAmount, uint burnAmount)
        external override onlyTrustedCaller
    {
        if (withdrawAmount > 0) {
            _payTokensTo(BLX, user, withdrawAmount);
        }
        if (burnAmount > 0) {
            //there is no special function for burn
            //BLX.burnFor(user, burnAmount);
            // we transfer burnAmount balance to burner
            // and burner would periodically burn them
            // on L2, it would mean transfer back to L1(by the burner)
            // then burn there
            // this is burning deposited BLX by the user
            // caller must ensure the balance is correct before calling this
            BLX.transfer(burner, burnAmount);
            emit BlxBurned(user, burnAmount);
        }
    }

    function takeTokensFrom(address _from, uint _amount)
    external override onlyTrustedCaller
    {
        _takeTokensFrom(USD, _from, _amount);
    }

    /// @dev distributes profit to staking
    /// only USD is distributed
    function distributeGainLoss()
        public override
    {
        uint totalUsdAmount = USD.balanceOf(address(this));
        address usdAddress = address(USD);
//        address blxAddress = address(BLX);

        (uint digital, uint american, uint turbo) = getPlatformProfits(usdAddress);

        require(
            digital + american + turbo < totalUsdAmount,
            "TR:NOT_ENOUGH_USD_DISTRIBUTE"
        );

        // no gap for now
//        require(
//            totalIncome[usdAddress] >= lockedCollateral + gapAmount[usdAddress],
//            "TR:DISTRIBUTE_NO_USD"
//        );

        // BLX is not distributed
//        require(
//            totalIncome[blxAddress] >= gapAmount[blxAddress],
//                "TR:DISTRIBUTE_NO_BLX"
//        );

        address stakingAddress = address(staking);
//        USD.safeTransfer(stakingAddress, usdAmount);
//        BLX.safeTransfer(stakingAddress, blxAmount);
        if (digital + american + turbo > 0) {
            IRewardsDistributionRecipient(stakingAddress)
                .notifyRewardAmount(digital, american, turbo);
        }
        {
            (uint _digital, uint _american, uint _turbo) = getPlatformLoss(usdAddress);
            if (_digital + _american + _turbo > 0) {
                IStakingContract(stakingAddress)
                    .notifyStakingLossAmount(_digital + _american + _turbo);
            }
        }

        _clearTokenBalance(usdAddress);
    }

    /// @dev address platform reward message
    function notifyPlatformReward(address token, uint reward) public override {
        address sender = _msgSender();
        require(sender == address(staking) || sender == address(blxStaking),"STR:ONLY_STAKING");
        uint b2 = reward * 125 / 1000;
        uint b1 = reward - b2;
        platformOwnIncome[token][platformBeneficiary1] += b1;
        platformOwnIncome[token][platformBeneficiary2] += b2;
        if (sender == address(blxStaking) && token == address(USD)) {
            // part of the blxStaking reward pool moved to platform beneficiaries
            if (blxStakingReward > reward) {
                blxStakingReward -= reward;
            }
            else {
                blxStakingReward = 0;
            }
        }
    }

    /// @dev address platform reward message
    function notifyBlxStakingReward(uint reward) public override {
        address sender = _msgSender();
        require(sender == address(blxStaking),"STR:ONLY_BLX_STAKING");
        blxStakingReward += reward;
    }

    // internal

    // pay & take tokens
    function _payTokensTo(IERC20 _token, address _to, uint _amount)
    internal
    {
        require(_amount > 0, "STR:ZERO_AMOUNT");
        require(_token.balanceOf(address(this)) >= _amount, "STR:SYS_NOT_ENOUGH_TOKEN");
        _token.safeTransfer(_to, _amount);
    }

    function _takeTokensFrom(IERC20 _token, address _from, uint _amount) internal
    {
        require(_amount > 0, "STR:ZERO_AMOUNT");
        require(_token.balanceOf(_from) >= _amount, "STR:USR_NOT_ENOUGH_TOKEN");
        require(_token.allowance(_from, address(this)) >= _amount, "STR:USR_NOT_ENOUGH_ALLWNC");
        _token.safeTransferFrom(_from, address(this), _amount);
    }

    // clear balances
    function _clearTokenBalance(address token) internal
    {
        delete balances[token][OptionLib.ProductKind.American];
        delete balances[token][OptionLib.ProductKind.Digital];
        delete balances[token][OptionLib.ProductKind.Turbo];
    }

    function _clearAllBalances() internal
    {
        _clearTokenBalance(address(USD));
        _clearTokenBalance(address(BLX));
    }
}

