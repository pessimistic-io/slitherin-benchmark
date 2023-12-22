pragma solidity ^0.8.0;

// Minimal interface for fetching stability rates from Maker DAO's Jug contract.
// Source: https://github.com/makerdao/dss/blob/master/src/jug.sol#L46

interface IMakerJug {
    struct Ilk {
        // Collateral-specific, per-second stability fee contribution [ray]
        uint256 duty;
        // Time of last drip [unix epoch time]
        uint256 rho;
    }

    function ilks(bytes32 ilk) external view returns (Ilk memory);

    function base() external view returns (uint256);
}

