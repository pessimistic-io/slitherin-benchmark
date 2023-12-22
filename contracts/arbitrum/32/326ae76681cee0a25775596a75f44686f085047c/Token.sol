// contracts/Token.sol
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./SafeMath.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract Token is ERC20, ERC20Burnable {
    // Using SafeMath
    using SafeMath for uint256;
    // Total supply
    uint256 private initialSupply = 1000000000 * (10 ** decimals());

    uint256 private _tokenSale;
    uint256 private _tokenLiquidity;
    uint256 private _tokenPartnership;
    uint256 private _tokenBurn;

    // Token Distribution
    uint256 public constant tokenSalePercentage = 28;
    uint256 public constant tokenLiquidityPercentage = 22;
    uint256 public constant tokenPartnershipPercentage = 10;
    uint256 public constant tokenBurnPercentage = 40;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _tokenSale = initialSupply.mul(tokenSalePercentage).div(100);
        _tokenLiquidity = initialSupply.mul(tokenLiquidityPercentage).div(100);
        _tokenPartnership = initialSupply.mul(tokenPartnershipPercentage).div(100);
        _tokenBurn = initialSupply.mul(tokenBurnPercentage).div(100);

        _mint(msg.sender, initialSupply);
    }

    /**
     * @dev Returns the amount of the Token Sales.
     * @return the number of vesting schedules
    */
    function getTokenSale() public view returns (uint256) {
        return _tokenSale;
    }

    /**
     * @dev Returns the amount of the Liquidity.
     * @return the number of vesting schedules
    */
    function getTokenLiquidity() public view returns (uint256) {
        return _tokenLiquidity;
    }

    /**
     * @dev Returns the amount of the Partners.
     * @return the number of vesting schedules
    */
    function getTokenPartnership() public view returns (uint256) {
        return _tokenPartnership;
    }

    /**
     * @dev Returns the amount of the Token Burn.
     * @return the number of vesting schedules
    */
    function getTokenBurn() public view returns (uint256) {
        return _tokenBurn;
    }
}

