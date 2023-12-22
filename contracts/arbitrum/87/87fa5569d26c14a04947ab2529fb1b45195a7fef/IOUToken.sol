// SPDX-License-Identifier: MIT

pragma solidity 0.7.5;

import "./ERC20.sol";
import "./Ownable.sol";

contract IOUToken is ERC20, Ownable {
    event MinterChanged(address indexed minter, bool indexed isMinter);

    mapping(address => bool) public isMinter;

    uint8 private decimals_;

    constructor(
        string memory name,
        string memory symbol,
        uint8 _decimals
    ) public ERC20(name, symbol) {
        decimals_ = _decimals;
    }


    /**
     * @dev Throws if the sender is not a whitelisted minter.
     */
    function _checkMinter() internal view virtual {
        require(isMinter[_msgSender()], "Caller is not allowed to mint");
    }
    /**
     * @dev Throws if called by any account other than a whitelisted minter.
     */
    modifier onlyMinter() {
        _checkMinter();
        _;
    }


    function mint(address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
    }


    function setMinter(address _to, bool _value) external onlyOwner {
        isMinter[_to] = _value;
        emit MinterChanged(_to, _value);
    }


    function decimals() public view virtual override returns (uint8) {
        return decimals_;
    }
}
