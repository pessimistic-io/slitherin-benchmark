// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./ERC20.sol";
import "./OwnableUpgradeable.sol";
import "./ERC20Upgradeable.sol";

import "./IDepositToken.sol";

contract DepositToken is IDepositToken, ERC20Upgradeable, OwnableUpgradeable {
    address public operator;

    function initialize(address _operator, address _lptoken)
        public
        initializer
    {
        require(_operator != address(0), "invalid _operator!");

        __Ownable_init();

        __ERC20_init_unchained(
            string(abi.encodePacked(ERC20(_lptoken).name(), " Quoll Deposit")),
            string(abi.encodePacked("quo", ERC20(_lptoken).symbol()))
        );

        operator = _operator;
    }

    function mint(address _to, uint256 _amount) external override {
        require(msg.sender == operator, "!authorized");

        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external override {
        require(msg.sender == operator, "!authorized");

        _burn(_from, _amount);
    }
}

