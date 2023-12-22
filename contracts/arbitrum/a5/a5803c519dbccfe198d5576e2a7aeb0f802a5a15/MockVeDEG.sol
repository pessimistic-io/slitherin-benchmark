// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ERC20.sol";

contract MockVeDEG is ERC20 {
    uint256 public constant MAX_UINT256 = type(uint256).max;

    uint8 public _decimals; //How many decimals to show.

    mapping(address => uint256) public locked;

    mapping(address => bool) public alreadyMinted;

    address public owner;

    constructor(
        uint256 _initialAmount,
        string memory _tokenName,
        uint8 _decimalUnits,
        string memory _tokenSymbol
    ) ERC20(_tokenName, _tokenSymbol) {
        require(_decimalUnits == 18);

        _mint(msg.sender, _initialAmount);

        _decimals = _decimalUnits; // Amount of decimals for display purposes

        owner = msg.sender;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address _user, uint256 _amount) public {
        if (msg.sender != owner) {
            require(_amount == 10000 ether, "Wrong amount");
            require(!alreadyMinted[_user], "Already minted");
        }
        alreadyMinted[_user] = true;
        _mint(_user, _amount);
    }

    function lockVeDEG(address _owner, uint256 _value) public {
        locked[_owner] += _value;
    }

    function unlockVeDEG(address _owner, uint256 _value) public {
        locked[_owner] -= _value;
    }
}

