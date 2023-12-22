// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";

abstract contract MintableERC20 is ERC20 {
    address public gov;
    address public pendingGov;

    mapping (address => bool) public isMinter;

    event NewPendingGov(address pendingGov);
    event UpdateGov(address gov);
    event SetMinter(address minter, bool isActive);

    modifier onlyGov() {
        require(gov == _msgSender(), "MintableERC20: forbidden");
        _;
    }
    
    modifier onlyMinter() {
        require(isMinter[msg.sender], "MintalbeERC20: forbidden");
        _;
    }

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        gov = _msgSender();
    }

    function setGov(address _gov) external onlyGov {
        pendingGov = _gov;
        emit NewPendingGov(_gov);
    }

    function acceptGov() external {
        require(_msgSender() == pendingGov);
        gov = _msgSender();
        emit UpdateGov(_msgSender());
    }

    function setMinter(address _minter, bool _isActive) external onlyGov {
        isMinter[_minter] = _isActive;
        emit SetMinter(_minter, _isActive);
    }

    function mint(address _account, uint256 _amount) external onlyMinter {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external onlyMinter {
        _burn(_account, _amount);
    }
}
