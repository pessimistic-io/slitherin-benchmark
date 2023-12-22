// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "./BaseTokenV2.sol";
import "./IMintable.sol";

abstract contract MintableBaseTokenV2 is BaseTokenV2, IMintable {

    uint8 public mintersCount;
    mapping(address => bool) public override isMinter;
    bool public privateTransferMode;
    mapping(address => bool) public whitelist;
    uint256[50] private __gap;

    event SetMinterRole(address indexed caller, address indexed recipient);
    event RevokeMinterRole(address indexed caller, address indexed recipient);
    event SetPrivateTransferMode(bool privateTransferMode);
    event SetWhitelist(address indexed caller, bool isWhitelist);

    modifier onlyMinter() {
        require(isMinter[msg.sender], "MintableBaseToken: Not minter role");
        _;
    }

    function _initialize(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) internal {
        super.initialize(_name, _symbol, _initialSupply);
    }

    function burn(address _account, uint256 _amount) external virtual onlyMinter override {
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

    function setPrivateTransferMode(bool _privateTransferMode) external onlyOwner {
        privateTransferMode = _privateTransferMode;
        emit SetPrivateTransferMode(_privateTransferMode);
    }

    function setWhitelist(address _caller, bool _isWhitelist) external onlyOwner {
        whitelist[_caller] = _isWhitelist;
        emit SetWhitelist(_caller, _isWhitelist);
    }

    function _transfer(address from, address to, uint256 value) internal virtual override {
        if (privateTransferMode) {
            require(whitelist[msg.sender], "Not in whitelist");
        }

        super._transfer(from, to, value);
    }
}


