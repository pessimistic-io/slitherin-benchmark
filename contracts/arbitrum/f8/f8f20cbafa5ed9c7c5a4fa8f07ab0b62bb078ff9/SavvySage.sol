// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./AccessControlUpgradeable.sol";
import "./EnumerableSet.sol";
import "./Math.sol";
import "./SafeMath.sol";

import "./Errors.sol";

import "./ISavvyPositionManager.sol";
import "./ITokenAdapter.sol";
import "./IYieldStrategyManager.sol";
import "./ISavvySage.sol";
import "./ISavvySwap.sol";

import "./FixedPointMath.sol";
import "./LiquidityMath.sol";
import "./SafeCast.sol";
import "./TokenUtils.sol";
import "./Checker.sol";
import "./IERC20TokenReceiver.sol";

/// @title  ISavvySage
/// @author Savvy DeFi
///
/// @notice An interface contract to buffer funds between the savvy and the SavvySwap
contract SavvySage is ISavvySage, AccessControlUpgradeable {
    using SafeMath for uint256;
    using FixedPointMath for FixedPointMath.Number;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN = keccak256("ADMIN");

    /// @notice The identifier of the keeper role.
    bytes32 public constant KEEPER = keccak256("KEEPER");

    /// @inheritdoc ISavvySage
    string public constant override version = "1.0.0";

    /// @notice The savvy address.
    address public savvy;

    /// @notice Slippage rate for MinimumAmountOut.
    uint16 public allowSlippageRate;

    /// @notice The scalar used for conversion of integral numbers to fixed point numbers.
    uint16 public constant FIXED_POINT_SCALAR = 1000;

    IYieldStrategyManager public yieldStrategyManager;

    /// @notice The public savvySwap address for each address.
    mapping(address => address) public savvySwap;

    /// @notice The flowRate for each address.
    mapping(address => uint256) public flowRate;

    /// @notice The last update timestamp for the flowRate for each address.
    mapping(address => uint256) public lastFlowRateUpdate;

    /// @notice The amount of flow available per ERC20.
    mapping(address => uint256) public flowAvailable;

    /// @notice The yieldTokens of each underlying supported by the Savvy.
    mapping(address => address[]) public _yieldTokens;

    /// @notice The total amount of an base token that has been swapped into the savvySwap, and has not been claimed.
    mapping(address => uint256) public currentSwapped;

    /// @notice The base tokens registered in the SavvySage.
    EnumerableSet.AddressSet private registeredBaseTokens;

    /// @notice The debt-token used by the SavvySage.
    address public debtToken;

    /// @notice A mapping of weighting schemas to be used in actions taken on the Savvy (burn, deposit).
    mapping(address => Weighting) public weightings;

    /// @dev A mapping of addresses to denote permissioned sources of funds
    mapping(address => bool) public sources;

    /// @dev A mapping of addresses to their respective AMOs.
    mapping(address => address) public amos;

    /// @dev A mapping of base tokens to divert to the AMO.
    mapping(address => bool) public divertToAmo;

    constructor() {
        _disableInitializers();
    }

    /// @dev Initialize the contract
    ///
    /// @param _admin     The governing address of the buffer.
    /// @param _debtToken The debt token borrowed by the Savvy and accepted by the SavvySwap.
    function initialize(
        address _admin,
        address _debtToken
    ) external initializer {
        __AccessControl_init_unchained();
        _grantRole(ADMIN, _admin);
        _grantRole(KEEPER, _admin);
        _setRoleAdmin(ADMIN, ADMIN);
        _setRoleAdmin(KEEPER, ADMIN);
        debtToken = _debtToken;
        allowSlippageRate = 100;
    }

    /// @dev Only allows the savvySwap to call the modified function
    ///
    /// Reverts if the caller is not a correct savvySwap.
    ///
    /// @param baseToken the base token associated with the savvySwap.
    modifier onlySavvySwap(address baseToken) {
        require(msg.sender == savvySwap[baseToken], "Unauthorized savvySwap");
        _;
    }

    /// @dev Only allows a governance-permissioned source to call the modified function
    ///
    /// Reverts if the caller is not a permissioned source.
    modifier onlySource() {
        require(sources[msg.sender], "Unauthorized source");
        _;
    }

    /// @dev Only calls from the admin address are authorized to pass.
    modifier onlyAdmin() {
        require(hasRole(ADMIN, msg.sender), "Unauthorized admin");
        _;
    }

    /// @dev Only calls from a keeper address are authorized to pass.
    modifier onlyKeeper() {
        require(hasRole(KEEPER, msg.sender), "Unauthorized keeper");
        _;
    }

    /// @inheritdoc ISavvySage
    function getWeight(
        address weightToken,
        address token
    ) external view override returns (uint256 weight) {
        return weightings[weightToken].weights[token];
    }

    /// @inheritdoc ISavvySage
    function getAvailableFlow(
        address baseToken
    ) external view override returns (uint256) {
        // total amount of collateral that the buffer controls in the savvy
        uint256 totalUnderlyingBuffered = getTotalUnderlyingBuffered(baseToken);

        if (totalUnderlyingBuffered < flowAvailable[baseToken]) {
            return totalUnderlyingBuffered;
        } else {
            return flowAvailable[baseToken];
        }
    }

    /// @inheritdoc ISavvySage
    function getRegisteredBaseTokens()
        external
        view
        override
        returns (address[] memory)
    {
        return registeredBaseTokens.values();
    }

    /// @inheritdoc ISavvySage
    function getTotalCredit() public view override returns (uint256 credit) {
        (int256 debt, ) = ISavvyPositionManager(savvy).accounts(address(this));
        credit = debt >= 0 ? 0 : SafeCast.toUint256(-debt);
    }

    /// @inheritdoc ISavvySage
    function getTotalUnderlyingBuffered(
        address baseToken
    ) public view override returns (uint256 totalBuffered) {
        totalBuffered = TokenUtils.safeBalanceOf(baseToken, address(this));
        for (uint256 i = 0; i < _yieldTokens[baseToken].length; i++) {
            totalBuffered += _getTotalBuffered(_yieldTokens[baseToken][i]);
        }
    }

    /// @inheritdoc ISavvySage
    function setWeights(
        address weightToken,
        address[] calldata tokens,
        uint256[] calldata weights
    ) external override onlyAdmin {
        Checker.checkArgument(
            tokens.length > 0 && tokens.length == weights.length,
            "invalid tokens and weights array length"
        );

        Weighting storage weighting = weightings[weightToken];
        delete weighting.tokens;
        weighting.totalWeight = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            address yieldToken = tokens[i];

            // For any weightToken that is not the debtToken, we want to verify that the yield-tokens being
            // set for the weight schema accept said weightToken as collateral.
            //
            // We don't want to do this check on the debtToken because it is only used in the burnCredit() function
            // and we want to be able to burn credit to any yield-token in the Savvy.
            if (weightToken != debtToken) {
                ISavvyPositionManager.YieldTokenParams
                    memory params = yieldStrategyManager
                        .getYieldTokenParameters(yieldToken);
                address baseToken = ITokenAdapter(params.adapter).baseToken();

                Checker.checkArgument(
                    weightToken == baseToken,
                    "invalid weightToken"
                );
            }

            weighting.tokens.push(yieldToken);
            weighting.weights[yieldToken] = weights[i];
            weighting.totalWeight += weights[i];
        }
    }

    /// @inheritdoc ISavvySage
    function setSource(address source, bool flag) external override onlyAdmin {
        Checker.checkArgument(sources[source] != flag, "already set");
        sources[source] = flag;
        emit SetSource(source, flag);
    }

    /// @inheritdoc ISavvySage
    function setSavvySwap(
        address baseToken,
        address newSavvySwap
    ) external override onlyAdmin {
        Checker.checkArgument(
            baseToken == ISavvySwap(newSavvySwap).baseToken(),
            "invalid base token"
        );
        savvySwap[baseToken] = newSavvySwap;
        emit SetSavvySwap(baseToken, newSavvySwap);
    }

    /// @inheritdoc ISavvySage
    function setSlippageRate(uint16 _slippageRate) external override onlyAdmin {
        /// slippage should be less than 30%.
        Checker.checkArgument(
            _slippageRate <= 300 && _slippageRate > 0,
            "invalid slippage rate"
        );
        allowSlippageRate = _slippageRate;

        emit SlippageRateSet(_slippageRate);
    }

    /// @inheritdoc ISavvySage
    function setSavvy(address _savvy) external override onlyAdmin {
        Checker.checkArgument(
            _savvy != address(0) && savvy != _savvy,
            "Invalid savvy address"
        );
        if (savvy != address(0)) {
            (, address[] memory depositedTokens) = ISavvyPositionManager(savvy)
                .accounts(address(this));
            Checker.checkState(
                depositedTokens.length == 0,
                "Have deposited base tokens"
            );
        }

        sources[savvy] = false;
        sources[_savvy] = true;

        if (savvy != address(0)) {
            _approveTo(savvy, 0);
        }

        savvy = _savvy;
        yieldStrategyManager = ISavvyPositionManager(savvy)
            .yieldStrategyManager();
        _approveTo(savvy, type(uint256).max);

        emit SetSavvy(savvy);
    }

    /// @inheritdoc ISavvySage
    function setAmo(
        address baseToken,
        address amo
    ) external override onlyAdmin {
        amos[baseToken] = amo;
        emit SetAmo(baseToken, amo);
    }

    /// @inheritdoc ISavvySage
    function setDivertToAmo(
        address baseToken,
        bool divert
    ) external override onlyAdmin {
        divertToAmo[baseToken] = divert;
        emit SetDivertToAmo(baseToken, divert);
    }

    /// @inheritdoc ISavvySage
    function registerToken(
        address baseToken,
        address _savvySwap
    ) external override onlyAdmin {
        Checker.checkState(
            yieldStrategyManager.isSupportedBaseToken(baseToken),
            "base token is not supported"
        );

        // only add to the array if not already contained in it
        Checker.checkState(
            !registeredBaseTokens.contains(baseToken),
            "already registered"
        );

        Checker.checkState(
            ISavvySwap(_savvySwap).baseToken() == baseToken,
            "invalid base token address"
        );

        savvySwap[baseToken] = _savvySwap;
        registeredBaseTokens.add(baseToken);
        TokenUtils.safeApprove(baseToken, savvy, 0);
        TokenUtils.safeApprove(baseToken, savvy, type(uint256).max);
        emit RegisterToken(baseToken, _savvySwap);
    }

    /// @inheritdoc ISavvySage
    function unregisterToken(
        address _baseToken,
        address _savvySwap
    ) external override onlyAdmin {
        Checker.checkState(
            registeredBaseTokens.contains(_baseToken),
            "already removed"
        );
        Checker.checkState(
            ISavvySwap(_savvySwap).baseToken() == _baseToken,
            "invalid base token address"
        );
        Checker.checkState(
            savvySwap[_baseToken] == _savvySwap,
            "invalid savvySwap address"
        );

        TokenUtils.safeApprove(_baseToken, savvy, 0);
        savvySwap[_baseToken] = address(0);
        registeredBaseTokens.remove(_baseToken);

        emit UnregisterToken(_baseToken, _savvySwap);
    }

    /// @inheritdoc ISavvySage
    function setFlowRate(
        address baseToken,
        uint256 _flowRate
    ) external override onlyAdmin {
        _swap(baseToken);

        flowRate[baseToken] = _flowRate;
        emit SetFlowRate(baseToken, _flowRate);
    }

    /// @inheritdoc IERC20TokenReceiver
    function onERC20Received(
        address baseToken,
        uint256 amount
    ) external override onlySource {
        if (divertToAmo[baseToken]) {
            _flushToAmo(baseToken, amount);
        } else {
            _updateFlow(baseToken);

            // total amount of collateral that the buffer controls in the savvy
            uint256 localBalance = TokenUtils.safeBalanceOf(
                baseToken,
                address(this)
            );

            // if there is not enough locally buffered collateral to meet the flow rate, swap only the swapped amount
            if (localBalance < flowAvailable[baseToken]) {
                currentSwapped[baseToken] += amount;
                ISavvySwap(savvySwap[baseToken]).swap(amount);
            } else {
                uint256 swappable = flowAvailable[baseToken] -
                    currentSwapped[baseToken];
                currentSwapped[baseToken] += swappable;
                ISavvySwap(savvySwap[baseToken]).swap(swappable);
            }
        }
    }

    /// @inheritdoc ISavvySage
    function swap(address baseToken) external override onlyKeeper {
        _swap(baseToken);
    }

    /// @inheritdoc ISavvySage
    function flushToAmo(
        address baseToken,
        uint256 amount
    ) external override onlyKeeper {
        require(divertToAmo[baseToken], "Failed to flush to AMO");
        _flushToAmo(baseToken, amount);
    }

    /// @inheritdoc ISavvySage
    function withdraw(
        address baseToken,
        uint256 amount,
        address recipient
    ) external override onlySavvySwap(baseToken) {
        Checker.checkArgument(
            amount <= flowAvailable[baseToken],
            "not enough flowAvailable amount"
        );

        uint256 localBalance = TokenUtils.safeBalanceOf(
            baseToken,
            address(this)
        );
        Checker.checkArgument(
            amount <= localBalance,
            "not enough local balance"
        );

        flowAvailable[baseToken] -= amount;
        currentSwapped[baseToken] -= amount;

        TokenUtils.safeTransfer(baseToken, recipient, amount);
    }

    /// @inheritdoc ISavvySage
    function withdrawFromSavvy(
        address yieldToken,
        uint256 shares,
        uint256 minimumAmountOut
    ) external override onlyKeeper {
        ISavvyPositionManager(savvy).withdrawBaseToken(
            yieldToken,
            shares,
            address(this),
            minimumAmountOut
        );
    }

    /// @inheritdoc ISavvySage
    function refreshStrategies() public override {
        address[] memory supportedYieldTokens = yieldStrategyManager
            .getSupportedYieldTokens();
        address[] memory supportedBaseTokens = yieldStrategyManager
            .getSupportedBaseTokens();

        Checker.checkState(
            registeredBaseTokens.length() == supportedBaseTokens.length,
            "invalid base tokens information"
        );

        // clear current strats
        for (uint256 j = 0; j < registeredBaseTokens.length(); j++) {
            delete _yieldTokens[registeredBaseTokens.at(j)];
        }

        uint256 numYTokens = supportedYieldTokens.length;
        for (uint256 i = 0; i < numYTokens; i++) {
            address yieldToken = supportedYieldTokens[i];

            ISavvyPositionManager.YieldTokenParams
                memory params = yieldStrategyManager.getYieldTokenParameters(
                    yieldToken
                );
            if (params.enabled) {
                _yieldTokens[params.baseToken].push(yieldToken);
            }
        }
        emit RefreshStrategies();
    }

    /// @inheritdoc ISavvySage
    function burnCredit() external override onlyKeeper {
        ISavvyPositionManager(savvy).syncAccount(address(this));
        uint256 credit = getTotalCredit();
        Checker.checkState(credit > 0, "zero credit amount");
        ISavvyPositionManager(savvy).borrowCredit(credit, address(this));

        _savvyAction(credit, debtToken, _savvyDonate);
    }

    /// @inheritdoc ISavvySage
    function depositFunds(
        address baseToken,
        uint256 amount
    ) external override onlyKeeper {
        Checker.checkArgument(amount > 0, "zero token amount");

        uint256 localBalance = TokenUtils.safeBalanceOf(
            baseToken,
            address(this)
        );
        Checker.checkArgument(
            localBalance >= amount,
            "not enough local balance"
        );
        _updateFlow(baseToken);

        // Don't deposit swapped funds into the Savvy.
        // Doing so puts those funds at risk, and could lead to users being unable to claim
        // their savvy swapped funds in the event of a vault loss.
        Checker.checkState(
            localBalance - amount >= currentSwapped[baseToken],
            "swapped over deposited amount"
        );
        _savvyAction(amount, baseToken, _savvyDeposit);
    }

    /// @dev Gets the total value of the yield tokens in units of base tokens that this contract holds.
    ///
    /// @param yieldToken The address of the target yield token.
    function _getTotalBuffered(
        address yieldToken
    ) internal view returns (uint256) {
        (uint256 balance, , ) = ISavvyPositionManager(savvy).positions(
            address(this),
            yieldToken
        );
        ISavvyPositionManager.YieldTokenParams
            memory params = yieldStrategyManager.getYieldTokenParameters(
                yieldToken
            );
        uint256 tokensPerShare = yieldStrategyManager.getBaseTokensPerShare(
            yieldToken
        );
        return (balance * tokensPerShare) / 10 ** params.decimals;
    }

    /// @dev Updates the available flow for a give base token
    ///
    /// @param baseToken the base token whos flow is being updated
    function _updateFlow(address baseToken) internal returns (uint256) {
        uint256 curTime = block.timestamp;
        // additional flow to be allocated based on flow rate
        uint256 marginalFlow = (curTime - lastFlowRateUpdate[baseToken]) *
            flowRate[baseToken];
        flowAvailable[baseToken] += marginalFlow;
        lastFlowRateUpdate[baseToken] = curTime;
        return marginalFlow;
    }

    /// @notice Runs an action on the Savvy according to a given weighting schema.
    ///
    /// This function gets a weighting schema defined under the `weightToken` key, and calls the target action
    /// with a weighted value of `amount` and the associated token.
    ///
    /// @param amount       The amount of funds to use in the action.
    /// @param weightToken  The key of the weighting schema to be used for the action.
    /// @param action       The action to be taken.
    function _savvyAction(
        uint256 amount,
        address weightToken,
        function(address, uint256) action
    ) internal {
        ISavvyPositionManager(savvy).syncAccount(address(this));

        Weighting storage weighting = weightings[weightToken];
        for (uint256 j = 0; j < weighting.tokens.length; j++) {
            address token = weighting.tokens[j];
            uint256 actionAmt = (amount * weighting.weights[token]) /
                weighting.totalWeight;
            action(token, actionAmt);
        }
    }

    /// @notice Donate credit weight to a target yield-token by burning debt-tokens.
    ///
    /// @param token    The target yield-token.
    /// @param amount      The amount of debt-tokens to burn.
    function _savvyDonate(address token, uint256 amount) internal {
        ISavvyPositionManager(savvy).donate(token, amount);
    }

    /// @notice Deposits funds into the Savvy.
    ///
    /// @param token  The yield-token to deposit.
    /// @param amount The amount to deposit.
    function _savvyDeposit(address token, uint256 amount) internal {
        uint256 minimumAmountOut = yieldStrategyManager
            .convertBaseTokensToShares(token, amount);
        minimumAmountOut =
            minimumAmountOut -
            (minimumAmountOut * allowSlippageRate) /
            FIXED_POINT_SCALAR;
        ISavvyPositionManager(savvy).depositBaseToken(
            token,
            amount,
            address(this),
            minimumAmountOut
        );
    }

    /// @notice Withdraws funds from the Savvy.
    ///
    /// @param token            The yield-token to withdraw.
    /// @param amountUnderlying The amount of underlying to withdraw.
    function _savvyWithdraw(address token, uint256 amountUnderlying) internal {
        uint8 decimals = TokenUtils.expectDecimals(token);
        uint256 pricePerShare = yieldStrategyManager.getBaseTokensPerShare(
            token
        );
        uint256 wantShares = (amountUnderlying * 10 ** decimals) /
            pricePerShare;
        (uint256 availableShares, , ) = ISavvyPositionManager(savvy).positions(
            address(this),
            token
        );
        if (wantShares > availableShares) {
            wantShares = availableShares;
        }
        // Allow 1% slippage
        uint256 minimumAmountOut = amountUnderlying -
            (amountUnderlying * allowSlippageRate) /
            FIXED_POINT_SCALAR;
        if (wantShares > 0) {
            ISavvyPositionManager(savvy).withdrawBaseToken(
                token,
                wantShares,
                address(this),
                minimumAmountOut
            );
        }
    }

    /// @notice Pull necessary funds from the Savvy and swap them.
    ///
    /// @param baseToken The base token to swap.
    function _swap(address baseToken) internal {
        _updateFlow(baseToken);

        uint256 totalUnderlyingBuffered = getTotalUnderlyingBuffered(baseToken);
        uint256 initialLocalBalance = TokenUtils.safeBalanceOf(
            baseToken,
            address(this)
        );
        uint256 want = 0;
        // Here we assume the invariant baseToken.balanceOf(address(this)) >= currentSwapped[baseToken].
        if (totalUnderlyingBuffered < flowAvailable[baseToken]) {
            // Pull the rest of the funds from the Savvy.
            want = totalUnderlyingBuffered - initialLocalBalance;
        } else if (initialLocalBalance < flowAvailable[baseToken]) {
            // totalUnderlyingBuffered > flowAvailable so we have funds available to pull.
            want = flowAvailable[baseToken] - initialLocalBalance;
        }

        if (want > 0) {
            _savvyAction(want, baseToken, _savvyWithdraw);
        }

        uint256 localBalance = TokenUtils.safeBalanceOf(
            baseToken,
            address(this)
        );
        uint256 swapDelta = 0;
        if (localBalance > flowAvailable[baseToken]) {
            swapDelta = flowAvailable[baseToken] - currentSwapped[baseToken];
        } else {
            swapDelta = localBalance - currentSwapped[baseToken];
        }

        if (swapDelta > 0) {
            currentSwapped[baseToken] += swapDelta;
            ISavvySwap(savvySwap[baseToken]).swap(swapDelta);
        }
    }

    /// @notice Flush funds to the amo.
    ///
    /// @param baseToken The baseToken to flush.
    /// @param amount          The amount to flush.
    function _flushToAmo(address baseToken, uint256 amount) internal {
        TokenUtils.safeTransfer(baseToken, amos[baseToken], amount);
        IERC20TokenReceiver(amos[baseToken]).onERC20Received(baseToken, amount);
    }

    function _approveTo(address _to, uint256 _approveAmount) internal {
        for (uint256 i = 0; i < registeredBaseTokens.length(); i++) {
            TokenUtils.safeApprove(
                registeredBaseTokens.at(i),
                _to,
                _approveAmount
            );
        }
        TokenUtils.safeApprove(debtToken, _to, _approveAmount);
    }

    uint256[100] private __gap;
}

