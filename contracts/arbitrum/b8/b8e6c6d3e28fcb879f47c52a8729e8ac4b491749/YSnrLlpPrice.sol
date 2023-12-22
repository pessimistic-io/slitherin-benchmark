// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./IPriceSource.sol";
import "./PRBMathUD60x18.sol";
import "./SnrLlpPrice.sol";
import "./IVault.sol";

/// @notice Returns the price of YsnrLLP
contract YSnrLlpPrice is IPriceSource {
    using PRBMathUD60x18 for uint256;
    
    SnrLlpPrice public immutable snrLlpPrice;
    IVault public immutable vault;

    constructor(SnrLlpPrice _snrLlpPrice, IVault _vault) {
        snrLlpPrice = _snrLlpPrice;
        vault = _vault;
    }

    /// @notice Returns the price of YsnrLLP
    function price() external view override returns (uint256) {
        return snrLlpPrice.price().mul(vault.getPricePerFullShare());
    }
}
