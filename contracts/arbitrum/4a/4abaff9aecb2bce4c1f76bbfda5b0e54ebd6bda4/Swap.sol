pragma solidity ^0.8.0;

import "./ISwap.sol";
import "./Interest.sol";
import "./IParameters.sol";

import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";

contract Swap is ISwap, Interest, OwnableUpgradeable, UUPSUpgradeable {
    // /// @notice Minimum allowed value of `leverage` in underlying
    // /// @dev prevents `leverage` `totalSupply` from growing too quickly and overflowing
    // uint constant MIN_EQUITY_TV = 10**13;

    IParameters public params;

    event BuyHedge    (address indexed buyer,  uint amount, uint value);
    event SellHedge   (address indexed seller, uint amount, uint value);
    event BuyLeverage (address indexed buyer,  uint amount, uint value);
    event SellLeverage(address indexed seller, uint amount, uint value);
    event ParametersChanged(address params);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _params) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        Interest.initialize();
        setParameters(_params);
    }

    /// @notice Buy into the protection buyer pool, minting `amount` hedge tokens
    function buyHedge(uint amount, address to) external {
        (uint fee, IModel model, IPrice price, IToken hedge, , IToken underlying) = params.get();
        uint potValue = underlying.balanceOf(address(this));
        uint _accrewedMul = accrewedMul();
        (uint value, uint tv) = _hedgeValue(
            amount, price.get(), hedge.totalSupply(), potValue, _accrewedMul
        );
        require(value > 0, "Zero value trade");
        value += value * fee / ONE;
        underlying.transferFrom(msg.sender, address(this), value);
        hedge.mint(to, amount);
        _updateRate(model, potValue + value, tv, _accrewedMul);
        emit BuyHedge(to, amount, value);
    }

    /// @notice Sell out of the protection buyer pool, burning `amount` hedge tokens
    function sellHedge(uint amount, address to) external {
        (uint fee, IModel model, IPrice price, IToken hedge, , IToken underlying) = params.get();
        uint potValue = underlying.balanceOf(address(this));
        uint _accrewedMul = accrewedMul();
        (uint value, uint tv) = _hedgeValue(
            amount, price.get(), hedge.totalSupply(), potValue, _accrewedMul
        );
        require(value > 0, "Zero value trade");
        value -= value * fee / ONE;
        underlying.transfer(to, value);
        hedge.burnFrom(msg.sender, amount);
        _updateRate(model, potValue - value, tv, _accrewedMul);
        emit SellHedge(to, amount, value);
    }

    /// @notice Buy into the protection seller pool, minting `amount` leverage tokens
    function buyLeverage(uint amount, address to) external {
        (uint fee, IModel model, IPrice price, IToken hedge, IToken leverage, IToken underlying) = params.get();
        uint potValue = underlying.balanceOf(address(this));
        uint _accrewedMul = accrewedMul();
        uint hedgeTV = _hedgeTV(potValue, hedge.totalSupply(), price.get(), _accrewedMul);
        uint leverageTV = potValue - hedgeTV;
        uint value = _leverageValue(amount, leverage.totalSupply(), leverageTV);
        require(value > 0, "Zero value trade");
        if (leverageTV > 0) {
            value += (value * fee / ONE) * hedgeTV / leverageTV;
        }
        underlying.transferFrom(msg.sender, address(this), value);
        leverage.mint(to, amount);
        _updateRate(model, potValue + value, hedgeTV, _accrewedMul);
        emit BuyLeverage(to, amount, value);
    }

    /// @notice Sell out of the protection seller pool, burning `amount` leverage tokens
    function sellLeverage(uint amount, address to) external {
        (uint fee, IModel model, IPrice price, IToken hedge, IToken leverage, IToken underlying) = params.get();
        uint potValue = underlying.balanceOf(address(this));
        uint _accrewedMul = accrewedMul();
        uint hedgeTV = _hedgeTV(potValue, hedge.totalSupply(), price.get(), _accrewedMul);
        uint leverageTV = potValue - hedgeTV;
        uint value = _leverageValue(amount, leverage.totalSupply(), leverageTV);
        require(value > 0, "Zero value trade");
        if (leverageTV > 0) {
            value -= (value * fee / ONE) * hedgeTV / leverageTV;
        }
        underlying.transfer(to, value);
        leverage.burnFrom(msg.sender, amount);
        _updateRate(model, potValue - value, hedgeTV, _accrewedMul);
        emit SellLeverage(to, amount, value);
    }

    /// @notice Value in underlying of `amount` hedge tokens
    function hedgeValue(uint amount) external view returns (uint, uint) {
        (, , IPrice price, IToken hedge, , IToken underlying) = params.get();
        uint _accrewedMul = accrewedMul();
        return _hedgeValue(amount, price.get(), hedge.totalSupply(), underlying.balanceOf(address(this)), _accrewedMul);
    }

    /// @notice Value in underlying of `amount` leverage tokens
    function leverageValue(uint amount) external view returns (uint) {
        (, , IPrice price, IToken hedge, IToken leverage, IToken underlying) = params.get();
        uint potValue = underlying.balanceOf(address(this));
        uint _accrewedMul = accrewedMul();
        return _leverageValue(amount, leverage.totalSupply(), potValue - _hedgeTV(potValue, hedge.totalSupply(), price.get(), _accrewedMul));
    }

    /// @notice Nominal value of 1 hedge token in underlying
    /// @dev underlying exchange rate + accrewed interest
    function hedgeValueNominal(uint amount) external view returns (uint) {
        (, , IPrice price, , , ) = params.get();
        return _hedgeValueNominal(amount, accrewedMul(), price.get());
    }

    /// @dev Would behoove some stakeholders to call this after a price change
    function updateInterestRate() external {
        (, IModel model, IPrice price, IToken hedge, , IToken underlying) = params.get();
        uint potValue = underlying.balanceOf(address(this));
        uint _accrewedMul = accrewedMul();
        _updateRate(model, potValue, _hedgeTV(potValue, hedge.totalSupply(), price.get(), _accrewedMul), _accrewedMul);
    }

    function setParameters(address _params) public onlyOwner {
        params = IParameters(_params);
        emit ParametersChanged(_params);
    }

    function _leverageValue(uint amount, uint supply, uint totalValue) internal pure returns (uint) {
        if (supply == 0) {
            return amount;
        }
        return amount*totalValue/supply;
    }

    function _hedgeValue(uint amount, uint price, uint supply, uint potValue, uint _accrewedMul) internal pure returns (uint, uint) {
        uint nomValue = _hedgeValueNominal(amount, _accrewedMul, price);
        uint nomTV    = _hedgeValueNominal(supply, _accrewedMul, price);
        if (potValue < nomTV)
            return (amount*potValue/supply, potValue);
        return (nomValue, nomTV);
    }

    function _hedgeTV(uint potValue, uint supply, uint price, uint _accrewedMul) internal pure returns (uint) {
        uint nomValue = _hedgeValueNominal(supply, _accrewedMul, price);
        if (potValue < nomValue)
            return potValue;
        return nomValue;
    }

    function _hedgeValueNominal(uint amount, uint _accrewedMul, uint price) internal pure returns (uint) {
        return amount * (_accrewedMul / ONE_8) / price;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}
}

