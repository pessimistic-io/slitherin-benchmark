// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ERC20.sol";

contract MockSHIELD is ERC20 {
    event Deposit(address indexed _from, uint256 _value);
    uint256 public constant MAX_UINT256 = type(uint256).max;

    uint8 public _decimals; //How many decimals to show.

    mapping(address => bool) public alreadyMinted;

    address public owner;

    constructor(
        uint256 _initialAmount,
        string memory _tokenName,
        uint8 _decimalUnits,
        string memory _tokenSymbol
    ) ERC20(_tokenName, _tokenSymbol) {
        require(_decimalUnits == 6);

        _mint(msg.sender, _initialAmount);

        owner = msg.sender;

        _decimals = _decimalUnits; // Amount of decimals for display purposes
    }

    function mint(address _to, uint256 _amount) public {
        if (msg.sender != owner) {
            require(_amount == 10000 * 10**6, "Wrong amount");
            require(!alreadyMinted[_to], "Already minted");
        }

        alreadyMinted[_to] = true;
        _mint(_to, _amount);
    }

    function burn(address _to, uint256 _amount) public {
        require(msg.sender == owner, "Only owner");

        _burn(_to, _amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function deposit(
        uint256 _type,
        address _token,
        uint256 _transfer,
        uint256 _minReceive
    ) public {
        if (_type == 1) {
            _mint(msg.sender, _minReceive);
            IERC20(_token).transferFrom(msg.sender, address(this), _transfer);
        } else revert("Wrong type");
    }
}

