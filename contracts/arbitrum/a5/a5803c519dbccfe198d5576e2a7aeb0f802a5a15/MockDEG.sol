// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ERC20.sol";

contract MockDEG is ERC20 {
    uint256 public constant MAX_UINT256 = type(uint256).max;

    uint8 public _decimals; //How many decimals to show

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

        owner = msg.sender;

        _decimals = _decimalUnits; // Amount of decimals for display purposes
    }

    /**
     * @notice Free mint
     */
    function mintDegis(address _account, uint256 _amount) external {
        _mint(_account, _amount);
    }

    /**
     * @notice This is for frontend mint
     */
    function mint(address _account, uint256 _amount) external {
        if (msg.sender != owner) {
            require(_amount == 100 ether, "Wrong amount");
            require(!alreadyMinted[_account], "Already minted");
        }

        alreadyMinted[_account] = true;
        _mint(_account, _amount);
    }

    function burnDegis(address _account, uint256 _amount) external {
        _burn(_account, _amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

