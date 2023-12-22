//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {Ownable} from "./Ownable.sol";
import {IOracle} from "./IOracle.sol";

contract FixedPrice is Ownable, IOracle {
    uint256 public price = 1e18;
    string public name;

    event PriceChange(uint256 timestamp, uint256 price);

    function _initialize(
        string memory _name,
        uint256 startingPrice,
        address _governance
    ) internal {
        name = _name;
        price = startingPrice;
        _transferOwnership(_governance);
    }

    function getPrice() public view override returns (uint256) {
        return price;
    }

    function fetchPrice() public view returns (uint256) {
        return price;
    }

    function getDecimalPercision() public pure override returns (uint256) {
        return 18;
    }

    function setPrice(uint256 _price) public onlyOwner {
        require(_price >= 0, "Oracle: price cannot be < 0");
        price = _price;
        emit PriceChange(block.timestamp, _price);
    }
}

