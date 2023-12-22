// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "./BaseToken.sol";
import "./IMintable.sol";

contract MintableBaseToken is BaseToken, IMintable {

    uint8 public mintersCount;
    mapping(address => bool) public override isMinter;

    event SetMinterRole(address indexed caller, address indexed recipient);
    event RevokeMinterRole(address indexed caller, address indexed recipient);

    modifier onlyMinter() {
        require(isMinter[msg.sender], "MintableBaseToken: Not minter role");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) BaseToken(_name, _symbol, _initialSupply) {}

    function burn(address _account, uint256 _amount) external onlyMinter override {
        _burn(_account, _amount);
    }

    function mint(address _account, uint256 _amount) external onlyMinter override {
        _mint(_account, _amount);
    }

    function setMinter(address _minter) external override onlyOwner {
        require(!isMinter[_minter], "MintableBaseToken: Already minter");
        isMinter[_minter] = true;
        mintersCount += 1;
        emit SetMinterRole(msg.sender, _minter);
    }

    function revokeMinter(address _minter) external override onlyOwner {
        require(isMinter[_minter], "MintableBaseToken: Not minter");
        isMinter[_minter] = false;
        mintersCount -= 1;
        emit RevokeMinterRole(msg.sender, _minter);
    }
}


