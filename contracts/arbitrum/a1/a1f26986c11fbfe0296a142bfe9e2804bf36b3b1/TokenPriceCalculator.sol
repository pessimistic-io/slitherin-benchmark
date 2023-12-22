// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./DAOAccessControlled.sol";
import "./ITokenPriceCalculator.sol";
import "./Initializable.sol";

contract TokenPriceCalculator is ITokenPriceCalculator, Initializable, DAOAccessControlled {

    // Amount of USD needed to mint 3 tokens(1 for entity, 1 for bartender and 1 for patron)
    uint256 public pricePerMint; // 6 decimals precision 9000000 = 9 USD

    function initialize(address _authority) public initializer{
        DAOAccessControlled._setAuthority(_authority);
    }

    function setPricePerMint(uint256 _price) external onlyGovernor {
        pricePerMint = _price;
        emit SetPricePerMint(_price);
    }

}
