pragma solidity ^0.8.0;

import "./IParameters.sol";

contract Parameters is IParameters {
    /// @notice Fee rate applied to notional value of trade.
    /// @notice Prevents soft frontrunning.
    /// @dev 18-decimal fixed-point
    uint immutable fee;

    /// @notice Interest rate model
    IModel immutable model;

    /// @notice Price of underlying in target asset
    IPrice immutable price;

    /// @notice Tokens representing the swap's protection buyers
    /// @notice Pegged to denominating asset + accrewed interest
    /// @dev Must use 18 decimals
    IToken immutable hedge;

    /// @notice Tokens representing the swap's protection sellers
    /// @notice Pegged to [R/(R-1)]x leveraged underlying
    /// @dev Must use 18 decimals
    IToken immutable leverage;

    /// @notice Token collateralizing hedge / underlying leverage
    /// @dev Must use 18 decimals
    IToken immutable underlying;

    constructor(
        uint _fee,
        IModel _model,
        IPrice _price,
        IToken _hedge,
        IToken _leverage,
        IToken _underlying)
    {
        fee        = _fee;
        model      = _model;
        price      = _price;
        hedge      = _hedge;
        leverage   = _leverage;
        underlying = _underlying;
    }

    function get() public view returns (uint, IModel, IPrice, IToken, IToken, IToken) {
        return (fee, model, price, hedge, leverage, underlying);
    }
}
