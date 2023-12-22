// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./AccessControlUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Metadata.sol";
import "./OvnMath.sol";
import "./IBalanceMath.sol";
import "./IHedgeStrategy.sol";
import "./IHedgeExchanger.sol";
import "./CommonModule.sol";
import "./console.sol";

abstract contract HedgeStrategy is IHedgeStrategy, CommonModule, Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant UNIT_ROLE = keccak256("UNIT_ROLE");

    IERC20 public asset;
    address public exchanger;
    address public balanceMath;
    uint256 public balanceSlippageBp;

    function __Strategy_init() internal initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        balanceSlippageBp = 100; // 1%
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    onlyRole(DEFAULT_ADMIN_ROLE)
    override
    {}

    // ---  modifiers

    modifier onlyExchanger() {
        require(exchanger == msg.sender, "Restricted to EXCHANGER");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Restricted to admins");
        _;
    }

    modifier onlyUnit() {
        require(hasRole(UNIT_ROLE, msg.sender) || IHedgeExchanger(exchanger).hasRole(UNIT_ROLE, msg.sender), "Restricted to Unit");
        _;
    }

    // --- setters

    function setExchanger(address _value) public onlyAdmin {
        require(_value != address(0), "Zero address not allowed");
        exchanger = _value;
    }

    function setBalanceMath(address _value) public onlyAdmin {
        require(_value != address(0), "Zero address not allowed");
        balanceMath = _value;
    }

    function setAsset(address _value) internal {
        require(_value != address(0), "Zero address not allowed");
        asset = IERC20(_value);
    }

    function setBalanceSlippageBp(uint256 _value) external onlyAdmin {
        balanceSlippageBp = _value;
    }
    // --- logic


    function stake(
        uint256 _amount
    ) external override onlyExchanger {
        _stake(_amount);
        emit Stake(_amount);
    }

    function unstake(
        uint256 _amount,
        address _to
    ) external override onlyExchanger returns (uint256) {
        _unstake(_amount);
        uint256 withdrawAmount = asset.balanceOf(address(this));
        require(withdrawAmount >= _amount, 'Returned value less than requested amount');

        asset.transfer(_to, _amount);
        emit Unstake(_amount, withdrawAmount);

        return _amount;
    }

    function claimRewards(address _to) external override onlyExchanger returns (uint256) {
        uint256 totalAsset = _claimRewards(_to);
        emit Reward(totalAsset);
        return totalAsset;
    }

    function balance(uint256 balanceRatio) external onlyExchanger override {
        _balance(balanceRatio);
    }

    function structBalance(BalanceParams calldata balanceParams) external onlyExchanger override {
        _structBalance(balanceParams);
    }

    function inchBalance(BalanceParams calldata balanceParams, CompoundSwap memory compoundSwap) external override onlyUnit returns(bool, uint256) {
        uint256 navExpected = OvnMath.subBasisPoints(netAssetValue(), balanceSlippageBp);
        (bool isDirectSwap, uint256 swapAmount) = _inchBalance(balanceParams, compoundSwap);
        require(netAssetValue() > navExpected, "nav less than expected");
        return (isDirectSwap, swapAmount);
    }

    function enter() external onlyUnit override {
        _enter();
    }

    function exit() external onlyUnit override {
        _exit();
    }

    function _claimRewards(address _to) internal virtual returns (uint256) {
        revert("Not implemented");
    }

    function _stake(uint256 _amount) internal virtual {
        revert("Not implemented");
    }

    function _unstake(uint256 _amount) internal virtual returns (uint256) {
        revert("Not implemented");
    }

    function _balance(uint256 balanceRatio) internal virtual {
        revert("Not implemented");
    }

    function _structBalance(BalanceParams calldata balanceParams) internal virtual {
        revert("Not implemented");
    }

    function _inchBalance(BalanceParams calldata balanceParams, CompoundSwap memory compoundSwap) internal virtual returns(bool, uint256) {
        revert("Not implemented");
    }

    function _enter() internal virtual {
        revert("Not implemented");
    }

    function _exit() internal virtual {
        revert("Not implemented");
    }

    function _calcDeltasAndExecActions(CalculationParams memory calculationParams) internal virtual {
        revert("Not implemented");
    }

    function _calcDeltas(CalculationParams memory calculationParams) internal virtual view returns (Action[] memory, Deltas memory) {
        revert("Not implemented");
    }

    function _execActions(Action[] memory actions) internal virtual {
        revert("Not implemented");
    }

    function _currentAmounts() internal virtual view returns (Amounts memory) {
        revert("Not implemented");
    }

    function getCurrentDebtRatio() public virtual view returns (int256) {
        revert("Not implemented");
    }

    function netAssetValue() public view override returns (uint256) {
        Liquidity memory liq = currentLiquidity();

        // add liquidity in free tokens
        int256 navUsd = liq.baseFree + liq.sideFree;
        // add liquidity in pool
        navUsd = navUsd + liq.sidePool + liq.basePool;
        // add liquidity in aave collateral minus borrow
        navUsd = navUsd + liq.baseCollateral - liq.sideBorrow;

        return usdToBase(toUint256(navUsd));
    }

    function balances() external view override returns(BalanceItem[] memory ){
        Liquidity memory liq = currentLiquidity();
        Amounts memory amounts = _currentAmounts();

        IHedgeStrategy.BalanceItem[] memory items = new IHedgeStrategy.BalanceItem[](6);
        items[0] = IHedgeStrategy.BalanceItem(address(baseToken), toUint256(liq.baseCollateral), amounts.baseCollateral, false);
        items[1] = IHedgeStrategy.BalanceItem(address(sideToken), toUint256(liq.sideBorrow), amounts.sideBorrow, true);
        items[2] = IHedgeStrategy.BalanceItem(address(baseToken), toUint256(liq.basePool), amounts.basePool, false);
        items[3] = IHedgeStrategy.BalanceItem(address(sideToken), toUint256(liq.sidePool), amounts.sidePool, false);
        items[4] = IHedgeStrategy.BalanceItem(address(baseToken), toUint256(liq.baseFree), amounts.baseFree, false);
        items[5] = IHedgeStrategy.BalanceItem(address(sideToken), toUint256(liq.sideFree), amounts.sideFree, false);
        return items;
    }

    function currentLiquidity() public view returns (Liquidity memory) {

        Amounts memory amounts = _currentAmounts();

        return Liquidity(
            toInt256(baseToUsd(amounts.baseCollateral)),
            toInt256(sideToUsd(amounts.sideBorrow)),
            toInt256(baseToUsd(amounts.basePool)),
            toInt256(sideToUsd(amounts.sidePool)),
            toInt256(baseToUsd(amounts.baseFree)),
            toInt256(sideToUsd(amounts.sideFree))
        );
    }

    function toUint256(int256 value) public pure returns (uint256) {
        require(value >= 0, "SafeCast: value must be positive");
        return uint256(value);
    }

    function toInt256(uint256 value) public pure returns (int256) {
        require(value <= uint256(type(int256).max), "SafeCast: value doesn't fit in an int256");
        return int256(value);
    }

    function baseToUsd(uint256 amount) public override view returns (uint256) {
        (uint80 roundID, int256 price, , uint256 timeStamp, uint80 answeredInRound) = baseOracle.latestRoundData();
        require(answeredInRound >= roundID, "Old data");
        require(timeStamp > 0, "Round not complete");
        return amount * uint256(price) / baseDecimals / 100;
    }

    function usdToBase(uint256 amount) public override view returns (uint256) {
        (uint80 roundID, int256 price, , uint256 timeStamp, uint80 answeredInRound) = baseOracle.latestRoundData();
        require(answeredInRound >= roundID, "Old data");
        require(timeStamp > 0, "Round not complete");
        return amount * 100 * baseDecimals / uint256(price);
    }

    function sideToUsd(uint256 amount) public override view returns (uint256) {
        (uint80 roundID, int256 price, , uint256 timeStamp, uint80 answeredInRound) = sideOracle.latestRoundData();
        require(answeredInRound >= roundID, "Old data");
        require(timeStamp > 0, "Round not complete");
        return amount * uint256(price) / sideDecimals / 100;
    }

    function usdToSide(uint256 amount) public override view returns (uint256) {
        (uint80 roundID, int256 price, , uint256 timeStamp, uint80 answeredInRound) = sideOracle.latestRoundData();
        require(answeredInRound >= roundID, "Old data");
        require(timeStamp > 0, "Round not complete");
        return amount * 100 * sideDecimals / uint256(price);
    }




    uint256[49] private __gap;
}

