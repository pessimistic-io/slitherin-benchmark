//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.2;

import "./ERC20Upgradeable.sol";
import "./console.sol";

contract VeGnome is ERC20Upgradeable {
    address private adm;
    address private owner;
    bool public initializedFlag;

    modifier isAdmin() {
        address contributor = 0xd50279D8881B97E78eb353A6cA26cEbBec2D295e; // veGNOME contributor for claim page airdrop
        require(_msgSender() == adm || _msgSender() == owner || _msgSender() == contributor, "This function can only be called by an admin");
        _;
    }

    function initialize(string memory name_, string memory symbol_, address admin_) public initializer {
        require(!initializedFlag, "Contract is already initialized");
        ERC20Upgradeable.__ERC20_init(name_, symbol_);
        adm = admin_;
        owner = _msgSender();
        initializedFlag = true;
    }

    function mint(address account_, uint256 amount_) public isAdmin() {
        _mint(account_, amount_);
    }

    function burn(address account_, uint256 amount_) public isAdmin() {
        _burn(account_, amount_);
    }

    function transfer(address recipient_, uint256 amount_) public override isAdmin() returns(bool) {
        _transfer(_msgSender(), recipient_, amount_);
        return true;
    }

    function transferFrom(
        address sender_,
        address recipient_,
        uint256 amount_
    ) public override isAdmin() returns (bool) {        
        _transfer(sender_, recipient_, amount_);

        uint256 currentAllowance = allowance(sender_, _msgSender());
        require(currentAllowance >= amount_, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender_, _msgSender(), currentAllowance - amount_);
        }

        return true;
    }

    function setAdmin(address newAdmin_) external isAdmin() {
        adm = newAdmin_;
    }

    function setOwner(address newOwner_) external isAdmin() {
        owner = newOwner_;
    }

    // function getAdmin() external view returns (address) {
    //     return adm;
    // }

    // function getOwner() external view returns (address) {
    //     return owner;
    // }
}

