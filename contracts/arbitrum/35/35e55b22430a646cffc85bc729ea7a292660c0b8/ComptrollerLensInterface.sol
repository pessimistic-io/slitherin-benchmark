pragma solidity ^0.8.17;

import "./VToken.sol";

interface ComptrollerLensInterface {
    function liquidateCalculateSeizeTokens(
        address comptroller,
        address vTokenBorrowed,
        address vTokenCollateral,
        uint actualRepayAmount
    ) external view returns (uint, uint);

    function getHypotheticalAccountLiquidity(
        address comptroller,
        address account,
        VToken vTokenModify,
        uint redeemTokens,
        uint borrowAmount
    )
        external
        view
        returns (
            uint,
            uint,
            uint
        );

    function liquidateBorrowAllowed(
        address comptroller,
        address vTokenBorrowed,
        address vTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount
    ) external view returns (uint);

    function redeemAllowed(
        address comptroller,
        address vToken,
        address redeemer,
        uint redeemTokens
    ) external view returns (uint);

    function seizeAllowed(
        address comptroller,
        address vTokenCollateral,
        address vTokenBorrowed,
        uint seizeTokens
    ) external returns (uint);

    function checkPartialBorrowAllowedAndReturn(
        address comptroller,
        address vToken,
        address borrower,
        uint borrowAmount
    ) external returns (uint);

    function isDeprecated(address comptroller, VToken vToken)
        external
        view
        returns (bool);
}

