// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "./ImooToken.sol";
import "./SafeMathUpgradeable.sol";
import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20.sol";
import "./IRateOracle.sol";

/**
 * @title Contract for Beefy Oracle
 * @notice Handles the ibt rate for mooTokens
 */
contract BeefyRateOracle is Initializable, IRateOracle {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20;

    IERC20 internal ibt;
    uint256 internal IBT_UNIT;

    function initialize(IERC20 _ibt) public virtual initializer {
        ibt = _ibt;
        IBT_UNIT = 10**ibt.decimals();
    }

    /**
     * @notice Getter for the rate of the IBT
     * @return the uint256 rate, IBT x rate must be equal to the quantity of underlying tokens
     */
    function getIBTRate() external view override returns (uint256) {
        return
            ImooToken(address(ibt)).balance().mul(IBT_UNIT).div(
                ImooToken(address(ibt)).totalSupply()
            );
    }
}

