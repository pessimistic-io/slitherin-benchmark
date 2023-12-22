// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Context.sol";
import "./SafeMath.sol";

contract veNimbusToken is ERC20, Ownable {
    using SafeMath for uint256;

    mapping(address => bool) public admins;

    modifier onlyAdmin {
        require(admins[_msgSender()], "FDB: Caller is not admin.");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {}

    function mint(address _receiver, uint256 _amount) external onlyAdmin {
        _mint(_receiver, _amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(
            false,
            "FBD: This token is not transferable."
        );

        super._transfer(from, to, amount);
    }

    ///
    /// Ownable actions
    ///

    function setAdmin(address _address, bool _value) external onlyOwner {
        admins[_address] = _value;
    }
   
}

